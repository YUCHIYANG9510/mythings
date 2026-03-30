# 📱 免費版測試指南 (Free Version Testing Guide)

## ✅ 當前狀態

已將測試模式切換為：
```swift
// PurchasesManager.swift 第 18 行
private let forceProForTesting = false  // ✅ 免費版測試模式
```

---

## 🎯 免費版限制一覽

### 限制清單

| 功能 | 免費版 | Pro 版 |
|------|--------|--------|
| **物品數量** | 最多 50 個 | ♾️ 無限 |
| **分類數量** | 最多 6 個 | ♾️ 無限 |
| **iCloud 同步** | ❌ 不可用 | ✅ 可用 |

### 程式碼定義位置

```swift
// PurchasesManager.swift 第 61-63 行
func canAddItem(currentCount: Int) -> Bool { 
    isPro || currentCount < 50 
}

func canAddCategory(currentCount: Int) -> Bool { 
    isPro || currentCount < 6 
}

var canUseICloud: Bool { 
    isPro 
}
```

---

## 🧪 測試清單

### 測試前準備

```
1. ✅ 確認 forceProForTesting = false
2. ✅ Clean Build (Cmd + Shift + K)
3. ✅ Build & Run
4. ✅ 檢查 Xcode Console 確認免費版：
   
   應該看到：
   [PM] applyCustomerInfo -> isPro=false
   
   不應該看到：
   [PM] 🧪 TESTING MODE: isPro forced to true
```

---

### 1️⃣ 物品數量限制測試（50 個上限）

#### 測試步驟 A: 新增第 50 個物品（應該成功）

```
1. 開啟 app
2. 新增 49 個物品（可以快速建立）
3. 嘗試新增第 50 個物品
4. ✅ 應該成功新增
5. 確認物品總數顯示為 50
```

#### 測試步驟 B: 新增第 51 個物品（應該顯示付費牆）

```
1. 已有 50 個物品的狀態下
2. 點擊「添加物品」按鈕
3. ✅ 應該立即彈出付費牆
4. ✅ 不會進入「新增物品」畫面
5. ✅ 付費牆應該顯示：
   - "My Things Premium"
   - "Unlimited Objects" 功能說明
   - "Annual" 和 "Lifetime" 兩個方案
```

#### 測試步驟 C: 相機拍照新增（已達上限）

```
1. 已有 50 個物品的狀態下
2. 嘗試點擊「相機」按鈕
3. ✅ 應該立即彈出付費牆
4. ✅ 不會開啟相機
```

#### 觀察 Console 輸出

```
// 達到上限時應該看到：
isPro=false
canAddItem(currentCount: 50) -> false
→ 顯示付費牆
```

---

### 2️⃣ 分類數量限制測試（6 個上限）

#### 測試步驟 A: 新增第 6 個分類（應該成功）

```
1. 進入「設定」→「管理分類」
2. 新增 5 個分類
3. 嘗試新增第 6 個分類
4. ✅ 應該成功新增
5. 確認分類總數為 6
```

#### 測試步驟 B: 新增第 7 個分類（應該顯示付費牆）

```
1. 已有 6 個分類的狀態下
2. 在「管理分類」中點擊「＋新增」
3. 或在「新增物品」頁面的「快速新增分類」輸入新分類名
4. ✅ 應該顯示付費牆
5. ✅ 不會新增分類
```

#### 測試步驟 C: 從「新增物品」頁面快速新增分類

```
1. 已有 6 個分類
2. 點擊「新增物品」
3. 在分類選擇頁面，嘗試「快速新增」新分類
4. ✅ 應該顯示「升級」按鈕（而非「新增」按鈕）
5. ✅ 點擊後應開啟付費牆
```

#### UI 狀態檢查

在 `AddItemView.swift` 的分類選擇頁面：
```
當 categoryStore.categories.count >= 6 時：

快速新增區域應該顯示：
┌─────────────────────────────────────┐
│ 📦  [輸入分類名稱]  [升級到 Pro ⭐️] │  ← 不是「新增」按鈕
└─────────────────────────────────────┘
```

---

### 3️⃣ iCloud 同步限制測試

#### 測試步驟 A: 檢查設定頁面

```
1. 進入「設定」
2. 查看「iCloud 同步」開關
3. ✅ 應該顯示 🔒 鎖定圖示
4. ✅ 開關應該是 OFF（灰色）
5. ✅ 點擊後應該顯示付費牆
```

#### 測試步驟 B: 嘗試開啟 iCloud 同步

```
1. 在設定頁面點擊「iCloud 同步」開關
2. ✅ 應該立即彈出付費牆
3. ✅ 開關不會變成 ON
4. ✅ 付費牆應該強調「iCloud Sync & Backup」功能
```

#### Console 檢查

```
免費版狀態：
isPro=false
canUseICloud -> false
iCloud Sync enabled: false
```

---

### 4️⃣ 付費牆 UI 測試

#### 檢查點 A: 付費牆內容完整性

```
✅ Header:
   - "My Things Premium" 標題
   - App icon 圖示
   - 副標題說明

✅ 功能說明卡片：
   - 📦 Unlimited Objects
   - 🗂️ Unlimited Categories  
   - ☁️ iCloud Sync & Backup
   - 每項都有詳細說明文字

✅ 方案選擇：
   - ○ Annual (如有試用期會顯示綠色標籤)
   - ○ Lifetime
   - 價格顯示正確（從 RevenueCat 取得）

✅ 底部按鈕：
   - "Subscribe annually" 或 "Buy lifetime"
   - Privacy Policy 連結
   - Terms 連結
   - Restore purchases 按鈕
```

#### 檢查點 B: 試用期顯示

```
如果年訂閱有設定試用期：

Annual 選項應該顯示：
┌─────────────────────────────────────┐
│ ○ Annual  [7-day free] 🟢          │
│   Billed annually                   │
│                             NT$ 390 │
└─────────────────────────────────────┘

Console 應該看到：
[PM] 🎁 Trial found for annual: 7-day free trial
[PM]    - Price after trial: NT$ 390.00
```

如果沒有試用期：
```
Console 應該看到：
[PM] ⚠️ No trial configured for annual
```

#### 檢查點 C: 互動測試

```
1. ✅ 可以在 Annual 和 Lifetime 之間切換
2. ✅ 選中的選項會顯示 ●（實心圓）
3. ✅ 底部按鈕文字會跟著改變
4. ✅ 可以下滑關閉付費牆（不強制購買）
5. ✅ 點擊「Restore purchases」應該有反應
```

---

### 5️⃣ 邊界情況測試

#### 測試 A: 正好 49 個物品

```
1. 新增 49 個物品
2. ✅ 可以新增第 50 個
3. ✅ 不會顯示付費牆
```

#### 測試 B: 正好 5 個分類

```
1. 新增 5 個分類
2. ✅ 可以新增第 6 個
3. ✅ 不會顯示付費牆
```

#### 測試 C: 刪除物品後再新增

```
1. 已有 50 個物品
2. 刪除 1 個物品（剩 49 個）
3. ✅ 應該可以再新增 1 個
4. 新增後達到 50 個
5. ✅ 嘗試再新增應該顯示付費牆
```

#### 測試 D: 刪除分類後再新增

```
1. 已有 6 個分類
2. 刪除 1 個分類（剩 5 個）
3. ✅ 應該可以再新增 1 個
4. 新增後達到 6 個
5. ✅ 嘗試再新增應該顯示付費牆
```

---

### 6️⃣ 多裝置測試（模擬新用戶體驗）

#### 模擬全新安裝

```
1. 刪除 app
2. 重新安裝（Build & Run）
3. ✅ 初始狀態：
   - 0 個物品
   - 0 個分類
   - isPro = false
   - iCloud 同步關閉
4. ✅ 新用戶可以：
   - 新增最多 50 個物品
   - 新增最多 6 個分類
   - 無法使用 iCloud 同步
```

---

## 📊 預期行為總結

### 免費版用戶體驗流程

```
新用戶下載 app
   ↓
可以免費使用基本功能
   ↓
新增 1-50 個物品 ✅
新增 1-6 個分類 ✅
   ↓
達到上限後
   ↓
看到付費牆 💳
   ↓
了解 Premium 功能
   ↓
選擇：
├─ 訂閱/購買 → 成為 Pro 用戶 ✅
└─ 取消 → 繼續使用免費版（受限）
```

---

## 🔧 快速切換測試模式

### 切換到免費版測試

```swift
// PurchasesManager.swift
#if DEBUG
private let forceProForTesting = false  // ✅ 免費版
#endif
```

### 切換到 Pro 版測試

```swift
// PurchasesManager.swift
#if DEBUG
private let forceProForTesting = true  // ✅ Pro 版
#endif
```

### ⚠️ 上架前必須做的事

```swift
// 1. 檢查測試標記
#if DEBUG
private let forceProForTesting = false  // ✅ 必須是 false
#endif

// 2. 或完全移除這個測試標記（更好）
// 只保留正常的 isPro 判斷邏輯
```

---

## ✅ 測試完成檢查表

在提交 App Store 前，確認以下項目：

### 免費版功能檢查

- [v] 可以新增最多 50 個物品
- [v] 第 51 個物品會顯示付費牆
- [v] 可以新增最多 6 個分類
- [v] 第 7 個分類會顯示付費牆
- [v] iCloud 同步選項顯示 🔒 並無法開啟
- [v] 點擊 iCloud 同步會顯示付費牆

### 付費牆檢查

- [v] 付費牆內容顯示正確（標題、功能說明、方案）
- [v] 價格從 RevenueCat 正確載入
- [v] 試用期資訊顯示正確（如有設定）
- [v] Annual 和 Lifetime 方案可正常切換
- [v] 可以下滑關閉付費牆
- [v] Privacy Policy 連結可正常開啟
- [v] Terms 連結可正常開啟
- [v] Restore purchases 功能正常

### Pro 版功能檢查（切換 forceProForTesting = true）

- [v] 可以新增超過 50 個物品
- [v] 可以新增超過 6 個分類
- [v] iCloud 同步可以開啟並正常運作
- [v] 設定頁面顯示 Pro 狀態
- [v] 不會看到付費牆

### 上架前檢查

- [ ] 移除或禁用 `forceProForTesting` 標記
- [ ] Console 不會輸出測試相關訊息
- [ ] App Store Connect 中產品已設定
- [ ] RevenueCat Dashboard 配置正確
- [ ] 隱私政策和服務條款連結正確
- [ ] 試用期設定符合預期（如有）

---

## 🎯 常見問題

### Q1: 如何快速建立 50 個測試物品？

```swift
// 可以在 ContentView.swift 暫時加上這個測試按鈕：

#if DEBUG
Button("🧪 Add 50 Test Items") {
    for i in 1...50 {
        let item = Item(
            name: "Test Item \(i)",
            imageName: "",
            categoryID: categoryStore.categories.first?.id,
            brand: "Test Brand",
            price: 100.0
        )
        items.append(item)
    }
    saveItems()
}
#endif
```

### Q2: 如何快速建立 6 個測試分類？

```swift
// 可以在 ManageCategoriesView 暫時加上：

#if DEBUG
Button("🧪 Add 6 Test Categories") {
    let emojis = ["📦", "🎧", "👕", "🍳", "📚", "⚽️"]
    for i in 1...6 {
        categoryStore.addCategory(
            name: "Category \(i)",
            emoji: emojis[i-1]
        )
    }
}
#endif
```

### Q3: 如何重置 app 回到全新狀態？

```
方法 1: 刪除 app 重裝
- 從裝置刪除 app
- Build & Run

方法 2: 清除本地資料
- 進入 app 資料夾
- 刪除 items.json 和 categories.json
- 重啟 app
```

### Q4: 如何測試「Restore purchases」？

```
需要 Sandbox 測試：

1. 設定 Sandbox test account
2. 在裝置上登入 Sandbox 帳號
3. 購買訂閱
4. 刪除 app 重裝
5. 點擊「Restore purchases」
6. ✅ 應該自動恢復 Pro 狀態
```

---

## 📝 測試記錄範本

建議複製這個表格，記錄你的測試結果：

```
測試日期：2025/___/___
測試裝置：iPhone ___
iOS 版本：___
App 版本：___

| 測試項目 | 預期結果 | 實際結果 | 通過 ✅ / 失敗 ❌ | 備註 |
|---------|---------|---------|----------------|------|
| 新增第 50 個物品 | 成功 | | | |
| 新增第 51 個物品 | 顯示付費牆 | | | |
| 新增第 6 個分類 | 成功 | | | |
| 新增第 7 個分類 | 顯示付費牆 | | | |
| 點擊 iCloud 同步 | 顯示付費牆 | | | |
| 付費牆 UI 完整性 | 所有元素正確 | | | |
| 試用期顯示 | 正確顯示（如有）| | | |
| 刪除後再新增 | 計數正確 | | | |

總結：
✅ 所有測試通過 / ⚠️ 有問題需要修復

問題列表：
1. 
2. 
```

---

## 🚀 開始測試！

現在你可以：

1. ✅ Clean Build (Cmd + Shift + K)
2. ✅ Build & Run
3. ✅ 按照上面的測試清單逐項測試
4. ✅ 記錄測試結果
5. ✅ 發現問題立即修復
6. ✅ 測試通過後準備上架！

---

**提醒**：測試完成後，記得將 `forceProForTesting` 設為 `false` 或完全移除，否則所有用戶都會是免費版狀態！

上架前的最終檢查：
```swift
// ❌ 錯誤 - 會導致所有人都無法使用 Pro 功能
private let forceProForTesting = true

// ✅ 正確 - 移除測試標記
// （此行已刪除）

// ✅ 或保持 false（但建議上架前完全移除）
private let forceProForTesting = false
```

祝測試順利！🎉
