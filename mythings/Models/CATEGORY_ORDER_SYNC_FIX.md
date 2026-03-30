# 🔧 Category 順序同步修復

## 問題描述

在 iCloud 同步時，發現：
- ✅ Items（物品）可以正確同步，順序一致
- ❌ Categories（分類）的順序在不同裝置上**不一致**

### 實際案例

**手機版的 Categories 順序：**
```
Device, New Category, Cake, Clothes, Sky, Food, Life, Box, Cool Stuff
```

**iPad 版的 Categories 順序：**
```
Device, New Category, Clothes, Sky, Food, Life, Cake, Box, Cool Stuff
```

可以看到 `Cake` 和 `Clothes` 的順序不同。

---

## 根本原因

### 原始程式碼問題（已修復）

在 `iCloudSyncManager.swift` 的 `pullCategories()` 函數中：

```swift
// ❌ 問題程式碼
var nameToBest: [String: (Category, Date?, CKRecord.ID, Int?)] = [:]

for r in all {
    // ... 處理 CloudKit records
    nameToBest[key] = (candidate, updatedAt, r.recordID, ord)
}

// ❌ Dictionary.values 的順序是不固定的！
let ordered = nameToBest.values.sorted { a, b in
    let ia = a.3 ?? Int.max
    let ib = b.3 ?? Int.max
    if ia != ib { return ia < ib }
    // ...
}
```

**問題點：**
1. **使用 Dictionary 儲存 categories**：Swift 的 Dictionary 是無序的集合
2. **`dictionary.values` 順序不固定**：即使後續用 `sorted()` 排序，但每次從 dictionary 取值的順序可能不同
3. **排序邏輯的後備方案不一致**：當沒有 `orderIndex` 時，會用 `updatedAt` 或名稱排序，但因為 dictionary 本身無序，結果不穩定

### 為什麼 Items 沒問題？

Items 的處理方式不同：
```swift
// ✅ Items 直接用 array 儲存
var local = loadLocalItems()
for r in all {
    // 直接操作 array，保持順序
    if let index = local.firstIndex(where: { $0.id == uuid }) {
        local[index] = merged
    }
}
local.sort { $0.createdAt > $1.createdAt }  // 固定的排序規則
```

---

## 修復方案

### 修改 1：`pullCategories()` - 完整同步

**改用 Array 取代 Dictionary，保持 CloudKit 回傳的順序**

```swift
// ✅ 修復後的程式碼
// Use Array instead of Dictionary to preserve CloudKit order
var cloudCategories: [(Category, Date?, CKRecord.ID, Int?, Int)] = []
var seenNames = Set<String>()

for (index, r) in all.enumerated() {
    // ... 處理 CloudKit records
    
    // Keep only the latest version for each category name
    if let existingIndex = cloudCategories.firstIndex(where: { 
        normalizeCategoryKey($0.0.name) == key 
    }) {
        let existingDate = cloudCategories[existingIndex].1 ?? .distantPast
        let newDate = updatedAt ?? .distantPast
        if newDate >= existingDate {
            cloudCategories[existingIndex] = (candidate, updatedAt, r.recordID, ord, index)
        }
    } else {
        cloudCategories.append((candidate, updatedAt, r.recordID, ord, index))
        seenNames.insert(key)
    }
}

// ✅ Sort by orderIndex (if available), then by original CloudKit order
cloudCategories.sort { a, b in
    // If both have orderIndex, use it
    if let ia = a.3, let ib = b.3 {
        return ia < ib
    }
    // If only one has orderIndex, it goes first
    if a.3 != nil { return true }
    if b.3 != nil { return false }
    // Otherwise preserve CloudKit query order (which respects sortDescriptors)
    return a.4 < b.4
}
```

**關鍵改進：**
1. ✅ 使用 **Array** 取代 Dictionary，保持順序
2. ✅ 記錄每個 record 在 CloudKit 回傳結果中的 **原始 index**（`a.4`, `b.4`）
3. ✅ 排序邏輯：
   - **第一優先**：有 `orderIndex` 的優先，並按 `orderIndex` 排序
   - **第二優先**：沒有 `orderIndex` 的，按 CloudKit query 回傳的順序（已經根據 `sortDescriptors` 排序）
4. ✅ 確保兩台裝置取得相同的 CloudKit 資料時，會有完全相同的排序結果

### 修改 2：`mergeCategoryChanges()` - 增量同步

**改善排序邏輯，確保一致性**

```swift
// ✅ 改進的排序邏輯
if !idToOrderIndex.isEmpty {
    local.sort { a, b in
        let ia = idToOrderIndex[a.id] ?? Int.max
        let ib = idToOrderIndex[b.id] ?? Int.max
        if ia != ib { return ia < ib }
        // If both don't have orderIndex, preserve relative order
        // by comparing names for consistency
        if ia == Int.max && ib == Int.max {
            return a.name.lowercased() < b.name.lowercased()
        }
        return ia < ib
    }
}
```

**關鍵改進：**
- ✅ 當兩個 category 都沒有 `orderIndex` 時，用**名稱字母順序**排序
- ✅ 確保在任何裝置上，相同的 categories 都會得到相同的排序結果

---

## 測試步驟

### 準備工作

1. **確保已登入 iCloud**
2. **確保已開啟 iCloud 同步**（設定 → iCloud 同步 = ON）
3. **準備兩台裝置**：iPhone 和 iPad（或兩台 iPhone/兩台 iPad）

### 測試方案 A：重新同步測試

#### Step 1：在裝置 1（例如 iPhone）建立特定順序的 categories

```
在 iPhone 上：
1. 開啟 app
2. 進入「設定」→「管理分類」
3. 建立以下 categories（按順序）：
   - Device 🎧
   - New Category 📦
   - Cake 🍰
   - Clothes 👕
   - Sky ☁️
   - Food 🍔
   - Life 🌱
   - Box 📦
   - Cool Stuff 😎

4. 確認順序正確
5. 等待同步完成（可以在設定中手動觸發同步）
```

#### Step 2：在裝置 2（例如 iPad）檢查順序

```
在 iPad 上：

方法 A - 重新安裝 app（推薦，測試首次同步）：
1. 刪除 app（如果已安裝）
2. 重新安裝 app
3. 登入相同 iCloud 帳號
4. 開啟 iCloud 同步
5. 等待同步完成
6. 檢查 categories 順序

方法 B - 清除本地資料（測試資料重載）：
1. 開啟 app
2. 進入「設定」→「Developer Options」（如有）
3. 點擊「Wipe Local Store」
4. 重啟 app
5. 開啟 iCloud 同步
6. 等待同步完成
7. 檢查 categories 順序
```

#### ✅ 預期結果

**兩台裝置的 categories 順序應該完全相同：**

```
✅ iPhone: Device, New Category, Cake, Clothes, Sky, Food, Life, Box, Cool Stuff
✅ iPad:   Device, New Category, Cake, Clothes, Sky, Food, Life, Box, Cool Stuff
```

---

### 測試方案 B：調整順序同步測試

#### Step 1：在裝置 1 調整順序

```
在 iPhone 上：
1. 進入「設定」→「管理分類」
2. 使用拖曳功能調整順序，例如：
   - 把 "Cake" 移到 "Clothes" 後面
   
原本：Device, New Category, Cake, Clothes, Sky, Food, Life, Box, Cool Stuff
調整後：Device, New Category, Clothes, Cake, Sky, Food, Life, Box, Cool Stuff

3. 等待同步完成
```

#### Step 2：在裝置 2 檢查

```
在 iPad 上：
1. 等待自動同步（或手動觸發同步）
2. 檢查 categories 順序
```

#### ✅ 預期結果

```
✅ iPhone: Device, New Category, Clothes, Cake, Sky, Food, Life, Box, Cool Stuff
✅ iPad:   Device, New Category, Clothes, Cake, Sky, Food, Life, Box, Cool Stuff
```

---

### 測試方案 C：多裝置編輯測試

#### 測試步驟

```
1. iPhone 和 iPad 都開啟 app
2. 在 iPhone 上調整 category 順序
3. 在 iPad 上新增一個 category
4. 等待兩邊都同步完成
5. 檢查順序是否一致
```

#### ✅ 預期結果

- 兩台裝置都有新增的 category
- 順序保持一致（以最後同步的順序為準）
- 沒有重複的 categories

---

## 驗證方法

### Console 輸出檢查

在 Xcode Console 中，同步時應該看到：

```
📂 Category name→ID map built with X categories:
   'cake' → UUID-1
   'clothes' → UUID-2
   'device' → UUID-3
   ...

✅ Pulled X categories from iCloud
📂 CategoryStore: Reloaded categories after iCloud sync
```

### 資料一致性檢查

1. **在兩台裝置上都進入「管理分類」**
2. **截圖比對**：確認順序完全相同
3. **計數檢查**：確認 category 數量相同
4. **逐一比對**：確認每個 category 的名稱、emoji 都相同

---

## 已知限制

### 1. 首次同步順序來源

- **首次同步**：如果是全新裝置，會完全採用 CloudKit 的順序
- **已有本地資料**：會合併本地和雲端的順序（雲端優先）

### 2. orderIndex 支援

- **現代裝置**：支援 `orderIndex` 欄位，順序由 CloudKit 的 `orderIndex` 決定
- **舊版本資料**：可能沒有 `orderIndex`，會按 CloudKit query 回傳順序（已按 `updatedAt` 排序）

### 3. 排序規則優先順序

```
1️⃣ 有 orderIndex → 按 orderIndex 排序（最可靠）
2️⃣ 沒有 orderIndex → 按 CloudKit query 回傳順序（已按 updatedAt 排序）
3️⃣ 增量同步且無 orderIndex → 按名稱字母順序（確保一致性）
```

---

## 技術細節

### CloudKit Query 的 sortDescriptors

```swift
if supportsOrderIndex {
    query.sortDescriptors = [
        NSSortDescriptor(key: "orderIndex", ascending: true),
        NSSortDescriptor(key: "updatedAt", ascending: false)
    ]
} else {
    query.sortDescriptors = [
        NSSortDescriptor(key: "updatedAt", ascending: false)
    ]
}
```

**保證：**
- CloudKit 會按照這些 sortDescriptors 回傳結果
- 在相同的 CloudKit 資料下，query 回傳順序是**一致的**
- 我們的修復確保**不會破壞這個順序**

### Array vs Dictionary 的差異

| 特性 | Array | Dictionary |
|------|-------|-----------|
| **順序** | ✅ 有序（insertion order） | ❌ 無序 |
| **重複 key** | ✅ 可以有重複元素 | ❌ key 唯一 |
| **適合場景** | 需要保持順序 | 需要快速查找 |

**我們的選擇：**
- 使用 **Array** 保存從 CloudKit 來的 categories
- 使用 **Set** 輔助去重（`seenNames`）
- 確保順序穩定且可預測

---

## 回歸測試清單

修復後，請確認以下功能正常：

### Categories 功能
- [ ] 新增 category
- [ ] 刪除 category  
- [ ] 重新命名 category
- [ ] 調整 category 順序（拖曳）
- [ ] Category emoji 修改

### iCloud 同步
- [ ] 完整同步（Full Sync）
- [ ] 增量同步（Incremental Sync）
- [ ] 刪除同步（DeletedCategory tombstone）
- [ ] 多裝置同步

### Items 相關
- [ ] Items 仍然可以正確同步
- [ ] Items 的 category 顯示正確
- [ ] Items 順序保持一致

### 邊界情況
- [ ] 重複名稱 category（應該去重）
- [ ] 空 category list
- [ ] 大量 categories（50+ 個）
- [ ] 網路中斷後恢復

---

## 效能影響

### 時間複雜度

**修復前：**
```
Dictionary 建構：O(n)
Dictionary.values.sorted()：O(n log n)
總計：O(n log n)
```

**修復後：**
```
Array 建構 + 去重檢查：O(n²) 最壞情況（實際上 n 很小，通常 < 20）
Array.sort()：O(n log n)
總計：O(n² + n log n) = O(n²)
```

**實際影響：**
- Category 數量通常 < 20 個
- O(n²) 在小 n 下非常快（< 1ms）
- **可以忽略不計**

### 記憶體使用

**修復前：**
```
Dictionary: 約 n * 80 bytes（估計）
```

**修復後：**
```
Array + Set: 約 n * 80 + n * 16 = n * 96 bytes（估計）
```

**實際影響：**
- 20 個 categories = 約 2KB 額外記憶體
- **可以忽略不計**

---

## 上線前檢查

- [ ] 已在兩台裝置上測試
- [ ] Category 順序同步正確
- [ ] Items 同步正常
- [ ] Console 無錯誤訊息
- [ ] 沒有重複 categories
- [ ] 刪除 category 可以同步
- [ ] 調整順序可以同步
- [ ] 網路斷線後恢復正常

---

## 相關檔案

- `iCloudSyncManager.swift`（主要修改）
  - `pullCategories()` 函數
  - `mergeCategoryChanges()` 函數
- `CategoryStore.swift`（接收同步通知）
- `ICLOUD_REVIEW.md`（整體 iCloud 同步架構文件）

---

## 修復日期

📅 2026/03/29

---

## 聯絡資訊

如果發現任何同步問題，請檢查：
1. Xcode Console 輸出
2. CloudKit Dashboard（查看實際資料）
3. 兩台裝置的 categories.json 檔案內容

祝同步順利！🎉
