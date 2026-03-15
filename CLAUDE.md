# ReceiptVault — Project Blueprint

> **⚠️ CRITICAL:** See `docs/superpowers/architecture.md` for detailed architecture decisions and rationale. That document is the source of truth and is kept current with every change.

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
- **All credentials are stored server-side in Lambda** — the app has NO secret keys.
- Only client-facing value: Lambda endpoint URL in `Config.xcconfig` (gitignored).
- Use the pre-commit hook to block credentials: `.githooks/pre-commit` runs before every commit.

### Architecture
- **`ReceiptParser` is the only module that talks to the backend.** It exposes:
  ```swift
  func parse(image: UIImage) async throws -> ReceiptData
  ```
- **Lambda handles all Claude API calls server-side.** The app sends image base64 → Lambda returns `ReceiptData`.
- **Core Data + CloudKit** for all storage (local + automatic iCloud sync).
- **No app-level Google auth, Google Drive, or Google Sheets.** Those are removed.

---

## What This App Does

An iOS app for managing receipts. Users add receipt photos via camera or photo library. The app sends images to a Lambda backend for structured extraction via Claude Vision API. Receipts are stored locally in Core Data with automatic iCloud CloudKit sync.

**Flow:**
1. User captures/selects receipt photo
2. App sends image to Lambda endpoint (`POST /parse-receipt`)
3. Lambda calls Claude Vision API (Anthropic key is server-side)
4. Lambda returns structured `ReceiptData`
5. App saves to Core Data
6. CloudKit automatically syncs to iCloud

---

## Current Architecture

### Modules
- **ReceiptParser** — Isolated service that takes `UIImage` and returns `ReceiptData`. Calls Lambda endpoint at `Config.lambdaEndpoint` with image base64. **No local API calls.**
- **ReceiptStoreCore** — Core Data + CloudKit storage. Handles all persistence and sync.
- **ProcessingPipeline** — Orchestrates image processing: validates → calls ReceiptParser → saves to ReceiptStore.
- **ProcessingController** — App-level controller for the pipeline. Manages UI state (loading, progress, errors).
- **Config** — Stores Lambda endpoint URL and other non-secret configuration.

**Removed modules (no longer needed):**
- ~~AuthManager~~ — Google Sign-In not needed; all auth is server-side.
- ~~DriveUploader~~ — Google Drive not used; using Core Data + CloudKit instead.
- ~~SheetsLogger~~ — Google Sheets not used.
- ~~PDFBuilder~~ — PDF generation not currently needed (receipts stored as metadata in Core Data).

### Key Design Principle

The app is a **thin client** — it only handles UI and storage. The Lambda backend handles all business logic:
- Receipt parsing (Claude Vision API)
- API authentication (Anthropic key)
- Future: PDF generation, email delivery, analytics, etc.

If parsing logic changes, only Lambda needs to update. The app is unaffected.

---

## Data Model

```swift
struct ReceiptData: Codable {
    let shopName: String
    let date: Date
    let total: Decimal?
    let currency: String?
    let lineItems: [LineItem]
    let rawText: String
}

struct LineItem: Codable {
    let name: String
    let quantity: Decimal?
    let unitPrice: Decimal?
    let totalPrice: Decimal?
}

// Core Data entity: CachedReceipt
@NSManaged public var shopName: String
@NSManaged public var date: Date
@NSManaged public var total: NSDecimalNumber?
@NSManaged public var currency: String?
@NSManaged public var lineItems: [LineItem]
@NSManaged public var rawText: String
@NSManaged public var driveFileId: String  // UUID of CloudKit record
```

---

## Storage Architecture

**Local:** Core Data with CloudKit sync enabled.
- Automatic iCloud sync across user's devices.
- No manual backend needed for storage.
- Offline-first: reads/writes work without network.

**Server:** Only Lambda function (for parsing).
- Stateless: receives image → returns data.
- No persistent storage on backend (that's what CloudKit is for).

---

## Tech Stack

- **UI:** SwiftUI (iOS 17.0+)
- **Local Storage:** Core Data + CloudKit
- **Receipt Parsing:** AWS Lambda + Claude Vision API (Anthropic SDK)
- **Image Input:** Camera (UIImagePickerController) + Photo Library (PhotosUI)
- **Backend:** AWS Lambda + API Gateway
- **Secrets Management:** AWS Secrets Manager (for Anthropic API key on backend)

---

## Removed Components

**Why Google integrations were removed:**
- Complexity: OAuth, token management, permission scopes
- Security: Client-side credential handling
- Maintenance: Google API changes, deprecated features
- Cost: Google Drive/Sheets API calls from millions of devices
- User friction: Sign-in flow, permissions dialogs

**Why CloudKit instead:**
- Automatic: Uses iCloud, zero user setup
- Secure: End-to-end encrypted via iCloud
- Private: Data stays on user's Apple account
- Free: Included in iCloud (100GB+ for most users)
- Simple: No backend auth needed
- Sync: Works across all user devices automatically

---

## Secrets Management

**What's NOT in the app:**
- Anthropic API key ❌
- AWS credentials ❌
- Google OAuth credentials ❌

**What IS in the app:**
- Lambda endpoint URL (Config.xcconfig, gitignored) ✅

**Where secrets live:**
- Lambda environment variables (AWS Secrets Manager)
- Pre-commit hook blocks credential patterns to prevent accidental commits

---

## Important Files

- `project.yml` — Xcode project definition (run `xcodegen generate` after changes)
- `Config.xcconfig` — Lambda endpoint URL (gitignored)
- `ReceiptVault/Sources/Pipeline/ReceiptParser.swift` — Backend communication
- `ReceiptVault/Sources/Storage/ReceiptStoreCore.swift` — Core Data + CloudKit
- `.githooks/pre-commit` — Security hook (blocks credentials)
