# Fix: Category Sync Order Issue

**Date**: March 27, 2026  
**Issue**: Items synced from iCloud show category as "Unknown"  
**Status**: ✅ Fixed

---

## Problem Description

When creating items with a category (e.g., "Device") on one device and syncing to iCloud, the items appeared with category "Unknown" on the second device.

### Root Cause

The sync operations were pulling **items BEFORE categories**, causing the following sequence:

1. Device A creates 3 items with category "Device" ✅
2. Device A pushes items to iCloud with `category = "Device"` (as string) ✅
3. Device A pushes category "Device" with its UUID to iCloud ✅
4. Device B syncs from iCloud:
   - 🔴 **Pulls items first** - tries to convert "Device" string → UUID
   - 🔴 `categoryNameToIDMap()` is empty (categories not synced yet!)
   - 🔴 Returns nil UUID (`00000000-0000-0000-0000-000000000000`)
   - Items are saved with nil UUID → show as "Unknown"
5. Device B then pulls categories - "Device" category appears ✅
6. But items already have nil UUID, so they remain "Unknown" ❌

---

## Solution

**Enforce correct sync order**: Categories must ALWAYS be synced BEFORE items.

### Changes Made

#### 1. Fixed `pullRemoteChanges()` (Incremental Sync)

**Before:**
```swift
private func pullRemoteChanges() async throws {
    try await pullItemsSince(lastItemSyncDate)
    try await pullCategoriesSince(lastCategorySyncDate)  // ❌ Too late!
}
```

**After:**
```swift
private func pullRemoteChanges() async throws {
    // ✅ CRITICAL FIX: Pull categories BEFORE items
    // This ensures categoryNameToIDMap() has all categories when processing items
    try await pullCategoriesSince(lastCategorySyncDate)
    try await pullItemsSince(lastItemSyncDate)
}
```

#### 2. Fixed `runFullSync()` (Full Sync)

**Before:**
```swift
private func runFullSync() async throws {
    // ... deletions and local load ...
    if !items.isEmpty { try await pushItemsWithRetry(items) }
    if !cats.isEmpty { try await pushCategoriesWithRetry(cats) }
    try await pullItems()
    try await pullCategories()  // ❌ Too late!
}
```

**After:**
```swift
private func runFullSync() async throws {
    // ... deletions and local load ...
    // ✅ Push categories before items
    if !cats.isEmpty { try await pushCategoriesWithRetry(cats) }
    if !items.isEmpty { try await pushItemsWithRetry(items) }
    // ✅ CRITICAL FIX: Pull categories BEFORE items
    try await pullCategories()
    try await pullItems()
}
```

#### 3. Fixed `pushLocalChanges()` (Incremental Push)

**Before:**
```swift
private func pushLocalChanges() async throws {
    let items = loadLocalItems()
    let categories = loadLocalCategories()
    let recentItems = items.filter { $0.updatedAt > watermark }
    if !recentItems.isEmpty { try await pushItemsWithRetry(recentItems) }  // ❌ Items first
    // ... then categories later
}
```

**After:**
```swift
private func pushLocalChanges() async throws {
    let items = loadLocalItems()
    let categories = loadLocalCategories()
    
    // ✅ Push categories first to ensure they exist before items reference them
    if timeSinceCatSync > clockSkewLeeway {
        if !categories.isEmpty { try await pushCategoriesWithRetry(categories) }
    }
    
    // Then push items
    let recentItems = items.filter { $0.updatedAt > watermark }
    if !recentItems.isEmpty { try await pushItemsWithRetry(recentItems) }
}
```

#### 4. Added Debug Logging

Enhanced `categoryNameToIDMap()` to log the mapping:

```swift
private func categoryNameToIDMap() -> [String: UUID] {
    var map: [String: UUID] = [:]
    let categories = loadLocalCategories()
    
    for cat in categories {
        let key = normalizeCategoryKey(cat.name)
        map[key] = cat.id
    }
    
    if !map.isEmpty {
        print("📂 Category name→ID map built with \(map.count) categories:")
        for (name, id) in map.sorted(by: { $0.key < $1.key }) {
            print("   '\(name)' → \(id)")
        }
    } else {
        print("⚠️ Category name→ID map is EMPTY! Items will get nil UUID.")
    }
    
    return map
}
```

Added logging when category lookup fails:

```swift
if resolvedCategoryID == UUID(uuidString: "00000000-0000-0000-0000-000000000000")! {
    print("⚠️ [Incremental Sync] Category '\(categoryName)' not found in local categories for item '\(name)'")
    print("   Item will show as 'Unknown' until categories are synced")
}
```

---

## Testing Steps

To verify the fix works:

### Test 1: New Category + Items
1. On Device A, create a new category "Electronics" 📱
2. On Device A, create 3 items with category "Electronics"
3. Wait for iCloud sync (check Settings → iCloud)
4. On Device B, pull to refresh or wait for auto-sync
5. ✅ **Expected**: All 3 items show "Electronics" category (not "Unknown")

### Test 2: Full Sync
1. On Device A, disable iCloud sync
2. Create category "Books" and 5 items in that category
3. Enable iCloud sync → triggers full sync
4. On Device B, check items
5. ✅ **Expected**: All 5 items show "Books" category

### Test 3: Simultaneous Creation
1. On Device A (offline), create category "Toys" and 2 items
2. On Device B (offline), create category "Games" and 3 items
3. Bring both devices online
4. Wait for sync to complete on both
5. ✅ **Expected**: Device A shows all 5 items with correct categories
6. ✅ **Expected**: Device B shows all 5 items with correct categories

### Test 4: Check Console Logs
Watch Xcode console for these logs:

```
📂 Category name→ID map built with 4 categories:
   'books' → 12345678-1234-1234-1234-123456789012
   'device' → 87654321-4321-4321-4321-210987654321
   'electronics' → ABCDEF01-2345-6789-ABCD-EF0123456789
   'games' → FEDCBA98-7654-3210-FEDC-BA9876543210
```

If you see:
```
⚠️ Category name→ID map is EMPTY! Items will get nil UUID.
```
Or:
```
⚠️ [Incremental Sync] Category 'Device' not found in local categories for item 'iPhone'
```

This indicates categories are not being pulled before items (should not happen with the fix).

---

## Why This Order Matters

### Data Flow

**Push Operation:**
```
Local Item (UUID categoryID) → CloudKit Record (String category)
```
- Converts `categoryID` (UUID) to `categoryName` (String) using `categoryIDToNameMap()`
- Order doesn't matter as much since we already have the UUID locally

**Pull Operation:**
```
CloudKit Record (String category) → Local Item (UUID categoryID)
```
- Converts `categoryName` (String) to `categoryID` (UUID) using `categoryNameToIDMap()`
- **CRITICAL**: `categoryNameToIDMap()` must have all categories loaded first!

### Key Insight

The sync system uses **string category names** in CloudKit records (for readability and backwards compatibility), but the app uses **UUID references** locally (for data integrity when categories are renamed).

This means:
- ✅ **Categories must be synced first** so the name→UUID map is populated
- ✅ Then items can be converted from string names to UUIDs correctly

---

## Related Files

- `iCloudSyncManager.swift` - Main sync logic (fixed)
- `Item.swift` - Uses `categoryID: UUID` field
- `Category.swift` - Category model with UUID
- `CategoryStore.swift` - Category persistence

---

## Prevention

To prevent this issue in the future:

1. **Never reorder** sync operations without understanding dependencies
2. **Always** pull/push categories before items
3. **Test** multi-device sync scenarios
4. **Watch** console logs for category mapping warnings

---

## Related Issues

- ✅ Fixed: Deleted categories reappearing (see `FIX_DELETED_CATEGORIES_REAPPEAR.md`)
- ✅ Fixed: iCloud sync timing issues (see `ICLOUD_FIXES_APPLIED.md`)

---

**Reviewed by**: AI Assistant  
**Tested on**: Pending user verification  
**Version**: 1.0
