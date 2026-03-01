# ReceiptVault — Project Blueprint

## What This App Does
An iOS app that lets the user share receipt photos from the Photos library directly into the app via a Share Extension. The app extracts structured data from the receipt using the Claude Vision API, saves the receipt as a PDF to Google Drive in an organized folder structure, logs metadata to a Google Sheet index, and writes a manifest JSON per folder.

---

## Architecture Overview

### Modules
- **ShareExtension** — iOS Share Extension that accepts images from Photos/Files and hands off to the main app via App Group
- **ReceiptParser** — Isolated service that takes a UIImage and returns structured ReceiptData. Currently calls Claude API directly; designed so internals can be swapped for a backend proxy later without changing callers
- **DriveUploader** — Handles all Google Drive API interactions: folder creation, PDF upload, manifest read/write
- **SheetsLogger** — Appends receipt metadata rows to a central Google Sheet index
- **PDFBuilder** — Converts UIImage + extracted text into a searchable PDF (image layer + invisible text layer)
- **AuthManager** — Manages Google Sign-In and OAuth token lifecycle for Drive + Sheets scopes

### Key Design Principle
`ReceiptParser` is the only module that knows about the Claude API. It exposes a single async function:
```swift
func parse(image: UIImage) async throws -> ReceiptData
```
When we add a backend later, only the internals of this function change. All other modules are unaffected.

---

## Data Model

```swift
struct ReceiptData: Codable {
    let shopName: String          // e.g. "Whole Foods"
    let date: Date                // receipt date, not scan date
    let total: Decimal?
    let currency: String?         // e.g. "USD"
    let lineItems: [LineItem]
    let rawText: String           // full OCR text, embedded in PDF
}

struct LineItem: Codable {
    let name: String
    let quantity: Decimal?
    let unitPrice: Decimal?
    let totalPrice: Decimal?
}
```

---

## Google Drive Structure

```
My Drive/
└── Receipts/
    └── {ShopName}/
        └── {YYYY}/
            └── {MM}/
                ├── {YYYY-MM-DD}_{ShopName}_{Total}.pdf
                └── manifest.json
```

### manifest.json schema
```json
{
  "lastUpdated": "ISO8601 timestamp",
  "receipts": [
    {
      "filename": "2025-03-15_Whole Foods_€47.20.pdf",
      "date": "2025-03-15",
      "shopName": "Whole Foods",
      "total": 47.20,
      "currency": "EUR",
      "driveFileId": "abc123",
      "lineItems": [...]
    }
  ]
}
```

### Central Index Sheet
One Google Sheet named `ReceiptVault Index` in the root of the Receipts folder.
Columns: `date | shopName | total | currency | lineItems (JSON) | driveFileId | driveFilePath | scannedAt`

---

## Share Extension Flow

1. User shares image from Photos → ShareExtension receives `NSItemProvider`
2. Extension saves image to shared App Group container (`group.com.yourname.receiptvault`)
3. Extension enqueues a job in UserDefaults (App Group) and triggers main app via `openURL`
4. Main app (or background task) picks up queued image, runs full pipeline:
   - `ReceiptParser.parse(image:)` → `ReceiptData`
   - `PDFBuilder.build(image:receiptData:)` → PDF with embedded text layer
   - `DriveUploader.upload(pdf:receiptData:)` → creates folders if needed, uploads PDF, updates manifest
   - `SheetsLogger.log(receiptData:driveFileId:)` → appends row to index Sheet
5. Local notification fires: "Receipt from {ShopName} saved ✓"

---

## API Keys & Secrets
- Claude API key: stored in iOS Keychain under key `anthropic_api_key`
- Google OAuth client ID: stored in `Config.xcconfig` (gitignored), injected into Info.plist
- Never hardcode secrets or commit them

## Backend Migration Path
When ready to add a backend proxy:
- `ReceiptParser` sends image to `POST /parse-receipt` on your server instead of Claude API directly
- Server holds the Anthropic API key
- No other files change
- Backend can be a Cloudflare Worker, Vercel function, or lightweight Express app

---

## Tech Stack
- **UI:** SwiftUI
- **Camera/Scan:** VisionKit (optional, secondary to Share Extension)
- **OCR/Extraction:** Claude API — `claude-sonnet-4-20250514`, vision input
- **Storage:** Google Drive API v3
- **Index:** Google Sheets API v4
- **Auth:** Google Sign-In SDK for iOS
- **PDF generation:** PDFKit (native iOS)
- **Minimum iOS:** 17.0

---

## Coding Conventions
- Async/await throughout, no completion handlers
- Each module in its own folder under `Sources/`
- Errors typed with custom `ReceiptVaultError` enum
- No force unwraps
- All API interaction wrapped so it can be unit tested with a mock

---

## Development Workflow

### xcodegen
- Run `xcodegen generate` whenever a Swift file is **added or deleted** — Xcode won't see it otherwise
- Do **not** run it when only editing existing files
- All custom Info.plist keys live in `project.yml` under `info.properties` — never edit the plist files directly, xcodegen overwrites them on regeneration
- Entitlements work the same way via `entitlements.properties` in `project.yml`

### Git / GitHub
- Remote: `https://github.com/ericeijkelenboom/ReceiptVault`
- Push via: `git -c credential.helper='!/opt/homebrew/bin/gh auth git-credential' push origin main`
