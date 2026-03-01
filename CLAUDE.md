# ReceiptVault — Project Blueprint

---

## Rules

These rules must always be followed, no exceptions.

### Build & Commit
- **Always build before committing.** Fix every error and warning before running `git commit`.
- Build command: `xcodebuild -scheme ReceiptVault -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug build`
- Push command: `git -c credential.helper='!/opt/homebrew/bin/gh auth git-credential' push origin main`

### xcodegen
- Run `xcodegen generate` whenever a Swift file is **added or deleted** — Xcode won't see it otherwise.
- Do **not** run it when only editing existing files — unnecessary and wastes time.
- All custom Info.plist keys live in `project.yml` under `info.properties` — never edit the plist files directly; xcodegen overwrites them on every regeneration.
- Entitlements are defined via `entitlements.properties` in `project.yml`, not in the entitlements files directly.

### Coding
- Async/await throughout — no completion handlers.
- No force unwraps.
- All errors typed using the `ReceiptVaultError` enum.
- Each module lives in its own folder under `Sources/`.
- All external API calls wrapped in a class so they can be unit-tested with a mock.

### Secrets
- Never hardcode secrets. Never commit them.
- Claude API key: stored in iOS Keychain under key `anthropic_api_key`.
- Google OAuth client ID: stored in `Config.xcconfig` (gitignored), injected into Info.plist via `project.yml`.

### Architecture
- `ReceiptParser` is the only module that knows about the Claude API.
- Never change the public signature `func parse(image: UIImage) async throws -> ReceiptData` — callers must stay unaffected when the implementation is swapped for a backend proxy.

---

## What This App Does
An iOS app for managing receipts. The user adds receipt photos via the camera or photo library. The app extracts structured data using the Claude Vision API, saves the receipt as a searchable PDF to Google Drive in an organised folder structure, and logs metadata to a Google Sheet index.

---

## Architecture Overview

### Modules
- **ReceiptParser** — Isolated service that takes a `UIImage` and returns `ReceiptData`. Currently calls Claude API directly; designed so internals can be swapped for a backend proxy later without changing callers.
- **DriveUploader** — Handles all Google Drive API interactions: folder creation, PDF upload, manifest read/write.
- **SheetsLogger** — Appends receipt metadata rows to a central Google Sheet index.
- **PDFBuilder** — Converts `UIImage` + extracted text into a searchable PDF (image layer + invisible CoreText layer).
- **AuthManager** — Manages Google Sign-In and OAuth token lifecycle for Drive + Sheets scopes.

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

## Backend Migration Path
When ready to add a backend proxy:
- `ReceiptParser` sends image to `POST /parse-receipt` on your server instead of Claude API directly.
- Server holds the Anthropic API key.
- No other files change.
- Backend can be a Cloudflare Worker, Vercel function, or lightweight Express app.

---

## Tech Stack
- **UI:** SwiftUI
- **OCR/Extraction:** Claude API — `claude-sonnet-4-20250514`, vision input
- **Storage:** Google Drive API v3
- **Index:** Google Sheets API v4
- **Auth:** Google Sign-In SDK for iOS
- **PDF generation:** PDFKit + CoreText (native iOS)
- **Minimum iOS:** 17.0
