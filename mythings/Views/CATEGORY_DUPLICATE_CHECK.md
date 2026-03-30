# 🚫 Category 名稱重複檢查功能

## 📋 功能說明

防止用戶建立或編輯 Category 時使用重複的名稱。

### 檢查規則

- ✅ **不區分大小寫**：`"Device"` 和 `"device"` 視為相同
- ✅ **忽略前後空白**：`"Device"` 和 `"  Device  "` 視為相同
- ✅ **空白名稱檢查**：不允許純空白或空字串
- ✅ **編輯模式例外**：編輯 Category 時，允許保留原本的名稱（只檢查是否與「其他」category 重複）

---

## 🛠️ 實作細節

### 1. `CategoryStore.swift` - 核心檢查方法

新增 `isDuplicateName()` helper 方法：

```swift
/// 檢查名稱是否已存在（不區分大小寫，忽略前後空白）
/// - Parameters:
///   - name: 要檢查的名稱
///   - excludingID: 排除特定 ID（用於編輯時，排除自己）
/// - Returns: true = 名稱已存在（重複）
func isDuplicateName(_ name: String, excludingID: UUID? = nil) -> Bool {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !trimmed.isEmpty else { return false }
    
    return categories.contains { category in
        // 如果有提供 excludingID，跳過該 category（編輯模式）
        if let excludeID = excludingID, category.id == excludeID {
            return false
        }
        return category.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == trimmed
    }
}
```

**使用場景：**
- **新增 Category**：`isDuplicateName("Device")` → 檢查是否已存在
- **編輯 Category**：`isDuplicateName("Device", excludingID: category.id)` → 檢查是否與「其他」category 重複（允許保留自己原本的名稱）

---

### 2. `AddCategoryView.swift` - 新增 Category 檢查

#### 修改內容

```swift
// ✅ 新增 alertMessage 狀態
@State private var alertMessage = ""

// ✅ Save 按鈕邏輯
Button {
    let trimmed = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
    
    if trimmed.isEmpty {
        alertMessage = "Please enter a category name"
        showAlert = true
    } else if categoryStore.isDuplicateName(trimmed) {
        alertMessage = "A category with this name already exists"
        showAlert = true
    } else {
        categoryStore.addCategory(name: trimmed, emoji: emoji)
        dismiss()
    }
}

// ✅ 更新 alert 顯示
.alert("Error", isPresented: $showAlert) {
    Button("OK", role: .cancel) { }
} message: {
    Text(alertMessage)
}
```

#### 使用者體驗流程

```
1. 使用者點擊「New Category」
2. 輸入名稱，例如 "Device"
3. 點擊「Save」
4. 檢查：
   ├─ 名稱為空？→ 顯示「Please enter a category name」
   ├─ 名稱已存在？→ 顯示「A category with this name already exists」
   └─ 都通過 → 儲存 Category，關閉視窗
```

---

### 3. `EditCategoryView.swift` - 編輯 Category 檢查

#### 修改內容

```swift
// ✅ 新增 alertMessage 狀態
@State private var alertMessage = ""

// ✅ Save 按鈕邏輯
Button {
    let trimmed = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
    
    if trimmed.isEmpty {
        alertMessage = "Please enter a category name"
        showAlert = true
    } else if categoryStore.isDuplicateName(trimmed, excludingID: category.id) {
        alertMessage = "A category with this name already exists"
        showAlert = true
    } else {
        let updatedCategory = Category(
            id: category.id,
            name: trimmed,
            emoji: emoji
        )
        categoryStore.updateCategory(category: updatedCategory)
        dismiss()
    }
}
```

#### 關鍵差異：`excludingID: category.id`

**為什麼需要 `excludingID`？**

```
情境：編輯現有 Category "Device"
├─ 使用者只改 emoji，名稱保持 "Device"
├─ 如果不排除自己，會誤判為「重複」
└─ 使用 excludingID: category.id，允許保留原名稱
```

**範例：**

```
現有 Categories：
1. Device 🎧
2. Clothes 👕
3. Food 🍔

編輯 "Device" → 改名為 "Clothes"：
❌ 檢查失敗（與 Category #2 重複）

編輯 "Device" → 保持 "Device"，只改 emoji：
✅ 檢查通過（excludingID 排除自己）
```

---

### 4. `AddItemView.swift` - 快速新增 Category

#### 原本邏輯（保留）

在「新增物品」頁面的「Category」選擇區，有「快速新增分類」功能。

**特殊行為：** 如果名稱已存在，**不顯示錯誤訊息**，而是**直接選中該 Category**。

```swift
private func addQuickCategory() {
    let trimmed = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }

    // 若名稱已存在，直接選中，不重複新增
    if categoryStore.isDuplicateName(trimmed) {
        if let existing = categoryStore.categories.first(where: { 
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == trimmed.lowercased() 
        }) {
            categoryID = existing.id
            newCategoryName = ""
            showCategorySheet = false
            return
        }
    }

    // 檢查免費版上限
    guard pm.canAddCategory(currentCount: categoryStore.categories.count) else {
        showCategorySheet = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            showPaywallFromCategory = true
        }
        return
    }

    categoryStore.addCategory(name: trimmed, emoji: newCategoryEmoji)
    categoryID = categoryStore.categories.last?.id
    newCategoryName = ""
    newCategoryEmoji = "📦"
    showCategorySheet = false
}
```

#### 使用者體驗流程

```
1. 使用者在「新增物品」頁面
2. 點擊「Category」→ 進入分類選擇
3. 在底部快速新增輸入框輸入 "Device"（已存在）
4. 點擊「新增」按鈕
5. ✅ 系統自動選中現有的 "Device" category
6. ✅ 關閉分類選擇視窗
7. ✅ 使用者看到已選中 "Device"
```

**設計理念：**
- **ManageCategoriesView**：明確的「管理分類」介面，應該嚴格檢查重複
- **AddItemView**：快速流程，重複名稱時「智慧選中」而非中斷流程

---

## 🧪 測試案例

### 測試 1：新增 Category - 空白名稱

```
步驟：
1. 進入「設定」→「Manage Categories」
2. 點擊「New Category」
3. 清空名稱欄位（或只輸入空白）
4. 點擊「Save」

✅ 預期結果：
- 顯示 Alert：「Please enter a category name」
- Category 不會被建立
```

---

### 測試 2：新增 Category - 重複名稱（完全相同）

```
現有 Categories：
- Device 🎧

步驟：
1. 點擊「New Category」
2. 輸入名稱：「Device」
3. 點擊「Save」

✅ 預期結果：
- 顯示 Alert：「A category with this name already exists」
- Category 不會被建立
```

---

### 測試 3：新增 Category - 重複名稱（大小寫不同）

```
現有 Categories：
- Device 🎧

步驟：
1. 點擊「New Category」
2. 輸入名稱：「device」（小寫）
3. 點擊「Save」

✅ 預期結果：
- 顯示 Alert：「A category with this name already exists」
- Category 不會被建立
- （因為不區分大小寫）
```

---

### 測試 4：新增 Category - 重複名稱（前後有空白）

```
現有 Categories：
- Device 🎧

步驟：
1. 點擊「New Category」
2. 輸入名稱：「  Device  」（前後有空白）
3. 點擊「Save」

✅ 預期結果：
- 顯示 Alert：「A category with this name already exists」
- Category 不會被建立
- （因為會 trim 空白後比較）
```

---

### 測試 5：新增 Category - 名稱不重複

```
現有 Categories：
- Device 🎧

步驟：
1. 點擊「New Category」
2. 輸入名稱：「Clothes」
3. 選擇 emoji：👕
4. 點擊「Save」

✅ 預期結果：
- Category 成功建立
- 視窗關閉
- 列表顯示新的 "Clothes 👕"
```

---

### 測試 6：編輯 Category - 保持原名稱

```
現有 Categories：
- Device 🎧
- Clothes 👕

步驟：
1. 點擊編輯「Device」
2. 名稱保持「Device」
3. 改變 emoji 為 📱
4. 點擊「Save」

✅ 預期結果：
- ✅ 儲存成功（允許保持原名稱）
- 視窗關閉
- 列表顯示更新後的 "Device 📱"
```

---

### 測試 7：編輯 Category - 改為重複名稱

```
現有 Categories：
- Device 🎧
- Clothes 👕

步驟：
1. 點擊編輯「Device」
2. 改名稱為「Clothes」
3. 點擊「Save」

✅ 預期結果：
- 顯示 Alert：「A category with this name already exists」
- Category 不會被更新
```

---

### 測試 8：編輯 Category - 改為新名稱

```
現有 Categories：
- Device 🎧
- Clothes 👕

步驟：
1. 點擊編輯「Device」
2. 改名稱為「Electronics」
3. 點擊「Save」

✅ 預期結果：
- ✅ 儲存成功
- 視窗關閉
- 列表顯示 "Electronics 🎧"
```

---

### 測試 9：快速新增（AddItemView）- 重複名稱

```
現有 Categories：
- Device 🎧

步驟：
1. 點擊「新增物品」
2. 點擊「Category」欄位
3. 在底部快速新增輸入框輸入「Device」
4. 點擊「新增」按鈕

✅ 預期結果：
- ✅ 不顯示錯誤訊息
- ✅ 自動選中現有的 "Device" category
- ✅ 關閉 Category 選擇視窗
- ✅ 回到新增物品頁面，Category 欄位顯示「Device」
```

---

### 測試 10：免費版上限 + 重複名稱

```
設定：forceProForTesting = false（免費版）
現有 Categories：6 個（已達上限）
- Device, Clothes, Food, Books, Sports, Toys

步驟：
1. 嘗試新增 Category「Device」（重複）
2. 點擊「Save」

✅ 預期結果：
- 顯示「A category with this name already exists」
- （重複檢查優先於數量限制）
- 不會顯示付費牆
```

---

## 🔍 邊界情況測試

### 邊界 1：名稱只有空白

```
輸入：「   」（只有空格）
✅ 預期：顯示「Please enter a category name」
```

---

### 邊界 2：名稱有特殊字元

```
現有：Device
輸入：Device!
✅ 預期：可以建立（視為不同名稱）

現有：Device!
輸入：device!
✅ 預期：重複（不區分大小寫）
```

---

### 邊界 3：emoji 不同，名稱相同

```
現有：Device 🎧
輸入：Device 📱
✅ 預期：重複（只比較名稱，不比較 emoji）
```

---

### 邊界 4：極長名稱

```
輸入：「MyVeryLongCategoryNameThatGoesOnAndOnAndOn...」（100+ 字元）
✅ 預期：可以建立（沒有長度限制）
```

---

### 邊界 5：Unicode 字元

```
現有：日本語
輸入：日本語
✅ 預期：重複（支援 Unicode）

現有：日本語
輸入：日本语
✅ 預期：可以建立（不同字）
```

---

## 📊 使用者體驗改善

### 改善前 ❌

```
使用者可以建立多個名稱相同的 Category：
- Device 🎧
- Device 📱
- device 💻

問題：
1. 列表混亂
2. 選擇時不知道選哪個
3. iCloud 同步可能衝突
```

### 改善後 ✅

```
系統會防止重複：
- Device 🎧  ← 只有一個

優點：
1. 列表清晰
2. 選擇時不會混淆
3. iCloud 同步穩定
4. 使用者體驗更好
```

---

## 🔄 與 iCloud 同步的關係

### iCloud 端的去重邏輯

在 `iCloudSyncManager.swift` 中，已經有基於名稱的去重邏輯：

```swift
// pullCategories() 中
let key = normalizeCategoryKey(name)  // 小寫 + trim
if let existingIndex = cloudCategories.firstIndex(where: { 
    normalizeCategoryKey($0.0.name) == key 
}) {
    // 保留最新版本
    if newDate >= existingDate {
        cloudCategories[existingIndex] = (candidate, updatedAt, r.recordID, ord, index)
    }
}
```

### 本地端防止重複的好處

- ✅ **防止上傳重複資料**：不會讓重複的 categories 進入 CloudKit
- ✅ **減少同步衝突**：避免在不同裝置建立同名 category 導致的合併問題
- ✅ **保持資料一致性**：確保本地和雲端的資料結構一致

---

## ⚠️ 注意事項

### 1. 區分大小寫

雖然系統會將 `"Device"` 和 `"device"` 視為重複，但：
- **儲存時保留使用者輸入的大小寫**
- 例如使用者輸入 `"Device"`，儲存的就是 `"Device"`（不會強制轉換）

### 2. Emoji 不參與比較

```
允許的情況：
- Device 🎧  → 改 emoji 為 📱 = Device 📱 ✅

不允許的情況：
- Device 🎧 存在時，新增 Device 📱 ❌（名稱重複）
```

### 3. 編輯時的例外

```
編輯 "Device" 時：
- 保持 "Device" → ✅ 允許（excludingID 排除自己）
- 改為 "Clothes"（已存在）→ ❌ 不允許
- 改為 "Electronics"（不存在）→ ✅ 允許
```

### 4. 快速新增的特殊邏輯

```
在 AddItemView 的快速新增：
- 重複名稱 → 自動選中現有 category ✅
- 不重複 → 建立新 category ✅
- 不會顯示錯誤訊息（使用者友善）
```

---

## 📝 相關檔案

- `CategoryStore.swift` - 核心檢查邏輯
- `AddCategoryView.swift` - 新增 Category UI
- `EditCategoryView.swift` - 編輯 Category UI
- `AddItemView.swift` - 快速新增 Category
- `ManageCategoriesView.swift` - Category 管理介面

---

## ✅ 測試清單

完整測試前，請確認：

- [ ] 空白名稱檢查正常
- [ ] 重複名稱（完全相同）檢查正常
- [ ] 重複名稱（大小寫不同）檢查正常
- [ ] 重複名稱（前後空白）檢查正常
- [ ] 編輯時可以保留原名稱
- [ ] 編輯時不可改為重複名稱
- [ ] 快速新增重複名稱時自動選中
- [ ] Alert 訊息正確顯示
- [ ] 與免費版上限檢查不衝突
- [ ] iCloud 同步不受影響

---

## 🎯 上線前檢查

- [ ] 所有測試案例通過
- [ ] 兩台裝置測試（iPhone + iPad）
- [ ] iCloud 同步正常
- [ ] Console 無錯誤訊息
- [ ] 使用者體驗流暢
- [ ] Alert 文字正確（英文/其他語言）

---

**修復日期：** 2026/03/29

祝測試順利！🎉
