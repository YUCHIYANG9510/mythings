# iCloud Sync - Testing Checklist

Use this checklist to verify all fixes are working correctly.

---

## 🧪 Test 1: Physical File Deletion

### Grid View Context Menu
- [ ] Long-press an item in grid view
- [ ] Tap "Delete"
- [ ] Item disappears from UI
- [ ] Navigate to Settings → Files app → mythings → Images
- [ ] Verify the image file is **deleted** (not just cached)

### List View Context Menu
- [ ] Long-press an item in list view
- [ ] Tap "Delete"
- [ ] Item disappears from UI
- [ ] Check Files app → Verify image deleted

### List View Swipe-to-Delete (NEW!)
- [ ] In list view, swipe left on an item
- [ ] Red "Delete" button appears with trash icon
- [ ] Tap Delete OR complete full swipe
- [ ] Item disappears from UI
- [ ] Check Files app → Verify image deleted

### iCloud Sync Verification
- [ ] Delete an item on Device A
- [ ] Wait 30 seconds
- [ ] Open app on Device B
- [ ] Verify item is deleted on Device B too
- [ ] Check that tombstone record exists in CloudKit

---

## 📡 Test 2: Network Monitoring

### Offline Behavior
- [ ] Enable Airplane Mode on device
- [ ] Open Settings → iCloud Sync
- [ ] Verify shows: "Network: 🔴 Unavailable"
- [ ] Try to add/edit an item
- [ ] Check console logs → Should see "⚠️ Network unavailable, sync deferred"
- [ ] No sync errors should occur

### Auto-Resume on Network Restore
- [ ] Keep app open with Airplane Mode on
- [ ] Disable Airplane Mode
- [ ] Watch Settings → Should change to "Network: 🟢 Available"
- [ ] Check console → Should see "📶 Network connection restored"
- [ ] Sync should automatically trigger
- [ ] Verify changes sync to iCloud within 30 seconds

### Network Status Display
- [ ] Open Settings → iCloud Sync
- [ ] Should see "Network" row with colored indicator
- [ ] Toggle WiFi on/off → Status updates in real-time
- [ ] Green circle = available, Red circle = unavailable

---

## 👤 Test 3: iCloud Account Status

### Sign Out Scenario
- [ ] Go to iOS Settings → [Your Name] → Sign Out
- [ ] Open app → Check Settings → iCloud Sync
- [ ] Should show error: "Please sign in to iCloud in Settings"
- [ ] iCloud Sync toggle should auto-disable
- [ ] No crashes or silent failures

### Sign Back In
- [ ] Sign back into iCloud in iOS Settings
- [ ] Open app (may need to force quit and reopen)
- [ ] iCloud sync should be available again
- [ ] Toggle it back on
- [ ] Verify sync resumes normally

### Restricted Account (If Available)
- [ ] Use Screen Time or MDM to restrict iCloud
- [ ] Open app → Check Settings
- [ ] Should show: "iCloud is restricted on this device"
- [ ] Sync should auto-disable
- [ ] No error spam in console

---

## 📱 Test 4: Swipe Actions in List View

### Basic Swipe
- [ ] Switch to List View mode
- [ ] Swipe left on any item (not too fast)
- [ ] Delete button should slide in from right
- [ ] Button is red with trash icon
- [ ] Text says "Delete"

### Partial Swipe → Tap Delete
- [ ] Swipe left halfway
- [ ] Release finger → Button stays visible
- [ ] Tap the Delete button
- [ ] Item should disappear immediately
- [ ] Confirm deletion worked

### Full Swipe Delete
- [ ] Swipe left quickly all the way across
- [ ] Item should delete immediately without tapping button
- [ ] "Full swipe" gesture should work like iOS Mail

### Multiple Deletions
- [ ] Delete 3 items in quick succession via swipe
- [ ] All should disappear smoothly
- [ ] No crashes or UI glitches
- [ ] All deletions should sync to iCloud

---

## 🔄 Test 5: Multi-Device Sync

### Setup
- [ ] Install app on 2+ devices with same iCloud account
- [ ] Enable iCloud Sync on all devices
- [ ] Wait for initial sync to complete on all devices

### Delete on Device A
- [ ] Delete an item on Device A (any method)
- [ ] Wait 10-30 seconds
- [ ] Force quit and reopen app on Device B
- [ ] Item should be deleted on Device B

### Delete Multiple Items
- [ ] Delete 5 items on Device A
- [ ] Wait 1 minute
- [ ] Check Device B → All 5 should be deleted
- [ ] Check Device C (if available) → All deleted

### Network Interruption During Sync
- [ ] Delete an item on Device A
- [ ] Immediately enable Airplane Mode on Device A
- [ ] Disable Airplane Mode after 30 seconds
- [ ] Deletion should sync once network returns
- [ ] Verify on Device B after 1 minute

---

## 💾 Test 6: Storage & Cleanup

### Before Testing
- [ ] Check storage: Settings → General → iPhone Storage → mythings
- [ ] Note the "Documents & Data" size

### Delete 10 Items
- [ ] Delete 10 items with images
- [ ] Wait 1 minute for cleanup

### Verify Cleanup
- [ ] Check storage again → Size should be smaller
- [ ] Navigate to Files app → mythings → Images
- [ ] Count remaining images → Should match item count
- [ ] No orphaned files with deleted item IDs

### Temp File Cleanup
- [ ] Add an item with large image (5MB+)
- [ ] Wait for upload to complete
- [ ] Navigate to Files → "On My iPhone" → mythings → Upload (temp folder)
- [ ] Should be empty or files < 24 hours old

---

## ⚡ Test 7: Performance

### Battery Life
- [ ] Fully charge device
- [ ] Enable iCloud Sync
- [ ] Use app normally for 1 day
- [ ] Check Battery Usage in Settings
- [ ] mythings should not be in top battery consumers
- [ ] No background activity when app closed

### Sync Speed
- [ ] Add 10 items in quick succession
- [ ] All should sync to iCloud within 2 minutes
- [ ] No sync failures or timeouts

### Offline Performance
- [ ] Enable Airplane Mode
- [ ] Use app normally (add, edit, delete items)
- [ ] Should work smoothly with no delays
- [ ] Disable Airplane Mode → All changes sync

---

## 🐛 Test 8: Edge Cases

### Rapidly Toggle Sync
- [ ] Settings → Toggle iCloud Sync on/off 5 times quickly
- [ ] No crashes
- [ ] Network monitor stops/starts properly
- [ ] Last state is respected

### App Restart During Sync
- [ ] Start a large sync operation (many items)
- [ ] Force quit app mid-sync
- [ ] Reopen app
- [ ] Sync should resume from where it left off
- [ ] No data corruption

### Delete Same Item on Two Devices
- [ ] Disable network on both devices
- [ ] Delete same item on Device A and Device B
- [ ] Re-enable network on both
- [ ] Wait 2 minutes
- [ ] Item should be deleted on both with no errors
- [ ] Tombstone handling should prevent conflicts

### iCloud Storage Full
- [ ] (If possible) Fill iCloud storage to limit
- [ ] Try to sync large images
- [ ] Should show error: "iCloud storage is full"
- [ ] Should offer guidance to free up space
- [ ] App should continue to work locally

---

## ✅ Test 9: UI/UX Verification

### Settings Screen
- [ ] Open Settings → iCloud Sync
- [ ] "Enable iCloud Sync" toggle works
- [ ] "Sync Status" shows current state
- [ ] "Network" row shows green/red indicator
- [ ] "Last Sync Time" shows formatted date/time
- [ ] Footer text updates based on sync state

### Error Messages
- [ ] Trigger various errors (no account, no network, etc.)
- [ ] All error messages are clear and actionable
- [ ] No technical jargon or error codes shown
- [ ] Users know what action to take

### Visual Feedback
- [ ] Deleting items feels instant (no lag)
- [ ] Swipe animations are smooth
- [ ] Network indicator updates in real-time
- [ ] No UI freezing during sync

---

## 📋 Final Checklist

### Code Quality
- [ ] No compiler warnings related to sync code
- [ ] No SwiftLint errors
- [ ] All methods have clear comments
- [ ] Console logs are informative (not spam)

### Documentation
- [ ] Read `ICLOUD_REVIEW.md` for full context
- [ ] Read `ICLOUD_FIXES_APPLIED.md` for fix details
- [ ] Understand what each fix does

### Deployment Readiness
- [ ] All tests above pass
- [ ] No crashes in common scenarios
- [ ] Battery usage is reasonable
- [ ] Storage cleanup works correctly
- [ ] Multi-device sync is reliable

---

## 🎉 Success Criteria

Mark this checklist complete when:
- ✅ All critical tests pass (Tests 1-5)
- ✅ No crashes or data loss
- ✅ Multi-device sync works reliably
- ✅ Physical files are properly deleted
- ✅ Network monitoring prevents wasted battery
- ✅ Error messages are clear and helpful

---

## 📝 Notes Section

Use this space to track issues found during testing:

### Issues Found:
1. 
2. 
3. 

### Issues Fixed:
1. 
2. 
3. 

### Performance Notes:
- Battery impact: 
- Sync speed: 
- Storage usage: 

---

**Tester**: _______________  
**Date**: _______________  
**Device**: _______________  
**iOS Version**: _______________  
**Result**: ☐ Pass  ☐ Fail  ☐ Needs Revision
