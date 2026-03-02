# Plan: Edit Receipt Metadata (shop name, date, total/currency)

## Context
Claude occasionally misreads receipt dates (locale format confusion), shop names, or totals. Users need a way to correct these three fields without re-scanning. Line items are out of scope for this feature. The edit must propagate to all three data stores that hold receipt metadata: the local cache, the Drive manifest, and the Sheets index.

## Architecture overview

Receipt metadata lives in three places — all keyed by `driveFileId`:
1. **Local cache** — `~/Documents/receipts_cache.json` via `ReceiptStore`
2. **Drive manifest** — `manifest.json` in the receipt's month folder, managed by `DriveUploader`
3. **Sheets index** — one row per receipt in `ReceiptVault Index`, managed by `SheetsLogger`

PDF filename and folder path are **not changed** on edit (file already uploaded, renaming adds complexity the user didn't request).

## Files to modify / create

1. `ReceiptVault/Sources/ReceiptStore/ReceiptStore.swift` — add `update(_:)`
2. `ReceiptVault/Sources/DriveUploader/DriveUploader.swift` — add `updateManifestEntry(...)`
3. `ReceiptVault/Views/ReceiptDetailView.swift` — add Edit toolbar button + sheet, change `let receipt` → `@State`
4. `ReceiptVault/Views/ReceiptEditView.swift` (**new file** → run `xcodegen generate`)

Note: Sheets index is **not updated** on edit — it's a secondary index; the manifest + local cache are the source of truth.

## Step-by-step implementation

### 1. `ReceiptStore` — add `update(_ receipt: CachedReceipt)`

```swift
func update(_ receipt: CachedReceipt) {
    guard let idx = receipts.firstIndex(where: { $0.driveFileId == receipt.driveFileId }) else { return }
    receipts[idx] = receipt
    receipts.sort { $0.date > $1.date }
    save()
}
```

### 2. `DriveUploader` — add `updateManifestEntry(...)`

Logic mirrors `deleteReceipt`: get parent folder ID from Drive file metadata, find manifest.json in that folder, update the entry in-place (preserving `filename` and `lineItems`), write back.

```swift
func updateManifestEntry(driveFileId: String, shopName: String, date: Date,
                         total: Decimal?, currency: String?) async throws {
    // Get parent folder ID (same pattern as deleteReceipt)
    var metaComponents = URLComponents(url: filesURL.appendingPathComponent(driveFileId),
                                       resolvingAgainstBaseURL: false)!
    metaComponents.queryItems = [URLQueryItem(name: "fields", value: "parents")]
    let metaData = try await perform(try await authorizedRequest(url: metaComponents.url!, method: "GET"))
    struct FileMeta: Decodable { let parents: [String]? }
    guard let parentId = (try? JSONDecoder().decode(FileMeta.self, from: metaData))?.parents?.first
    else { throw ReceiptVaultError.uploadFailure("Could not find receipt folder on Drive") }

    // Find, load, and update the manifest
    guard let manifestId = try await findItem(name: "manifest.json", parentId: parentId) else { return }
    let existing = try await downloadFile(fileId: manifestId)
    var manifest = (try? JSONDecoder().decode(Manifest.self, from: existing)) ?? Manifest()

    let df = DateFormatter()
    df.dateFormat = "yyyy-MM-dd"
    df.locale = Locale(identifier: "en_US_POSIX")
    guard let idx = manifest.receipts.firstIndex(where: { $0.driveFileId == driveFileId }) else { return }
    let old = manifest.receipts[idx]
    manifest.receipts[idx] = ManifestEntry(
        filename: old.filename,                              // preserve — no rename
        date: df.string(from: date),
        shopName: shopName,
        total: (total as NSDecimalNumber?)?.doubleValue,
        currency: currency,
        driveFileId: driveFileId,
        lineItems: old.lineItems                            // preserve
    )
    manifest.lastUpdated = ISO8601DateFormatter().string(from: Date())

    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    try await updateFileContent(fileId: manifestId, data: try encoder.encode(manifest),
                                mimeType: "application/json")
}
```

### 3. `ReceiptDetailView` — Edit button + sheet

- Change `let receipt: CachedReceipt` → `@State private var receipt: CachedReceipt` with a custom `init(receipt:)` so the view reflects updates after save without changing `ReceiptsView`'s `NavigationLink(value:)` pattern.
- Add `@State private var showEdit = false` and `@State private var editError: String?`.
- Add an "Edit" `ToolbarItem` at `.topBarTrailing`.
- Present `ReceiptEditView` as a sheet; in the `onSave` callback: update `self.receipt`, call `receiptStore.update(updated)`, and fire a background `Task` to call `driveUploader.updateManifestEntry(...)`. On failure, set `editError`.
- Add `.alert` for `editError` (reuse the same pattern as `syncError` in `ReceiptsView`).

### 4. `ReceiptEditView` (new file)

A `NavigationStack` wrapping a `Form` with:

| Section | Control | Notes |
|---------|---------|-------|
| Shop | `TextField` | Required — Save disabled if empty after trimming |
| Date | `DatePicker(.graphical)` | `.date` components only |
| Total | `TextField(.decimalPad)` | Parse with `Decimal(string:)`, replace `,` → `.` |
| Total | `TextField` for currency | Force uppercase, capped at 3 chars via `onChange` |

Toolbar: "Cancel" (leading, dismisses without saving) + "Save" (trailing, bold).

`init(receipt:onSave:)` pre-fills all fields from the passed `CachedReceipt`. On Save: build updated `CachedReceipt`, call `onSave(updated)`, dismiss.

```swift
private func save() {
    let parsedTotal = Decimal(string: totalString.replacingOccurrences(of: ",", with: "."))
    let updated = CachedReceipt(
        driveFileId: original.driveFileId,
        shopName: shopName.trimmingCharacters(in: .whitespaces),
        date: date,
        total: parsedTotal,
        currency: currency.isEmpty ? nil : currency,
        scannedAt: original.scannedAt,
        lineItems: original.lineItems
    )
    onSave(updated)
    dismiss()
}
```

## xcodegen

Run `xcodegen generate` after creating `ReceiptEditView.swift`.

## Known limitations (out of scope)
- PDF filename in Drive is not renamed when shopName/date/total changes
- Sheets index row is not updated (manifest + local cache are the source of truth)
- Folder is not moved if shopName changes to a different store

## Verification
1. Build succeeds, no errors or warnings
2. Tapping Edit opens a sheet with pre-filled values for all four fields
3. Changing shop name → Save → list and detail view both show the new name immediately
4. After a Drive sync (`syncFromDrive`), the new name is still correct (manifest was updated)
5. Cancel discards all changes, nothing persists
6. Empty shop name disables the Save button
7. Decimal total parses correctly with both `.` and `,` as the decimal separator
8. Currency is forced to uppercase and capped at 3 characters while typing
9. Drive update failure shows an error alert without corrupting local data
