# ReceiptVault Architecture — Authoritative Guide

**Last Updated:** 2026-03-15
**Status:** Current (post-security-incident redesign)

> This document is the source of truth for ReceiptVault's architecture. All architectural decisions, rationale, and implementation details live here. When future agents join, start with this document to understand the system design.

---

## System Overview

ReceiptVault is a **thin-client mobile app** backed by a **stateless Lambda function**. The app's only responsibility is UI and local persistence. All business logic (receipt parsing, API calls) lives on the backend.

```
┌─────────────┐      HTTP      ┌─────────────┐
│   iOS App   │◄─────────────►│    Lambda   │
│ (UI + Data) │  POST /parse   │  (Parsing)  │
└─────────────┘                └─────────────┘
      │
      │ CloudKit
      ▼
┌─────────────┐
│   iCloud    │
│  (Backup)   │
└─────────────┘
```

---

## Architecture Decisions & Rationale

### Decision 1: Server-Side Credentials (Mar 2026)

**What changed:** Moved Anthropic API key from app to Lambda.

**Why:**
- **Security:** Client-side credentials expose keys if device is compromised or app is reverse-engineered.
- **Control:** Can rotate keys without app update; can monitor API usage per-user server-side.
- **Cost:** Prevent API key leakage; can rate-limit per-user server-side.
- **Maintenance:** Easier to update API version/model on backend without shipping app updates.

**Implementation:**
- `ReceiptParser.swift` now POSTs to `Config.lambdaEndpoint` with image base64.
- Lambda holds Anthropic API key in environment variables (via AWS Secrets Manager).
- App has zero knowledge of any API keys.

**Trade-off:** Requires network connectivity for receipt parsing (no offline parsing).

---

### Decision 2: Core Data + CloudKit Storage

**What it is:** All receipt data stored locally in Core Data with CloudKit sync enabled.

**Why:**
- **Simplicity:** No OAuth flow, permission dialogs, or token refresh needed.
- **Privacy:** Data encrypted in transit and at rest on iCloud; never touches our servers.
- **Automatic sync:** Works across all user devices without any app logic.
- **Zero backend storage:** App has no central database; data lives on user's iCloud.
- **Cost:** Free (included in iCloud); no API usage fees.
- **Offline-first:** Reads and writes work without network connectivity.

**Implementation:**
- Core Data schema with CloudKit sync enabled (`NSPersistentCloudKitContainer`)
- `CachedReceipt` entity stores all receipt data (shop, date, total, currency, items, text)
- CloudKit automatically handles sync, conflict resolution, and cross-device availability

---

### Decision 3: Stateless Lambda (not persistent backend)

**What changed:** Lambda only parses; doesn't store data.

**Why:**
- **Simplicity:** No database schema, migrations, or queries.
- **Scalability:** Handles infinite concurrent requests; no connection pooling, no state management.
- **Cost:** Pay only for execution time (not idle connections, storage, or compute).
- **Cold starts acceptable:** Receipt parsing is async; user sees progress spinner anyway.
- **Cloud agnostic:** Easy to migrate to different serverless (Vercel, Cloudflare, GCP).

**What Lambda does:**
```
POST /parse-receipt
├─ Receive: { image: "base64..." }
├─ Call Claude Vision API (Anthropic SDK)
├─ Extract structured data (ReceiptData)
└─ Return: { shopName, date, total, currency, lineItems, rawText }
```

**What Lambda does NOT do:**
- Store receipts (that's CloudKit)
- Generate PDFs (app could do this locally, or defer to future feature)
- Send emails (could be added as Lambda trigger later)
- Track user accounts (not needed; app uses iCloud identity)

---

## Current Module Structure

### ReceiptParser (Sources/ReceiptParser/ReceiptParser.swift)

**Responsibility:** Single point of contact with backend.

**Public interface:**
```swift
func parse(image: UIImage) async throws -> ReceiptData
```

**Implementation:**
```swift
// 1. Convert image to JPEG base64
let jpegData = image.jpegData(compressionQuality: 0.8)
let base64String = jpegData?.base64EncodedString()

// 2. POST to Lambda
var request = URLRequest(url: URL(string: "\(Config.lambdaEndpoint)/parse-receipt")!)
request.httpMethod = "POST"
request.setValue("application/json", forHTTPHeaderField: "Content-Type")
request.httpBody = try JSONEncoder().encode(["image": base64String])

// 3. Parse response and return ReceiptData
let (data, _) = try await URLSession.shared.data(for: request)
let result = try JSONDecoder().decode(ReceiptData.self, from: data)
return result
```

**Why this design:**
- **Testable:** Can mock with different implementation (e.g., offline mode, test data)
- **Future-proof:** If we add PDF generation or email, it happens in Lambda; app doesn't change
- **Simple:** No credential handling, no async loops, no retry logic (let caller handle that)

### ProcessingPipeline (Sources/Pipeline/ProcessingPipeline.swift)

**Responsibility:** Orchestrate the image-to-storage flow.

**Owned by:** `ProcessingController`

**Public interface:**
```swift
func process(image: UIImage, onProgress: (String) -> Void) async throws
```

**Steps:**
1. Call `ReceiptParser.parse(image)` → get `ReceiptData`
2. Call `ReceiptStoreCore.saveReceipt(data)` → save to Core Data + trigger CloudKit sync
3. Notify UI with progress

### ProcessingController (Sources/Pipeline/ProcessingController.swift)

**Responsibility:** App-level state machine for the processing flow.

**Owned by:** ReceiptVaultApp (via @StateObject)

**Published state:**
- `isProcessing: Bool` — is a receipt currently being processed?
- `pendingCount: Int` — how many images left in queue?
- `totalInBatch: Int` — total images in current batch?
- `processingStep: String?` — current step (e.g., "Extracting text…")
- `lastError: ReceiptVaultError?` — last error encountered

**Responsibility:**
- Queue image processing (allows batch uploads)
- Run ProcessingPipeline asynchronously
- Update UI state as processing progresses
- Capture and expose errors for user feedback

### ReceiptStoreCore (Sources/Storage/ReceiptStoreCore.swift)

**Responsibility:** Core Data + CloudKit persistence.

**Owned by:** ReceiptVaultApp (via @StateObject)

**Public interface:**
```swift
// Fetch all receipts
func fetchAllReceipts() async throws -> [CachedReceipt]

// Save a receipt
func saveReceipt(data: ReceiptData, jpgPath: String) async throws

// Delete a receipt
func deleteReceipt(id: UUID) async throws

// Query receipts by search text
func grouped(searchText: String) -> [ReceiptGroup]
```

**Core Data schema:**
```
CachedReceipt
├─ id: UUID (primary key)
├─ shopName: String
├─ date: Date
├─ total: NSDecimalNumber?
├─ currency: String?
├─ lineItems: [LineItem] (codable)
├─ rawText: String
├─ driveFileId: String (UUID of CloudKit sync)
├─ createdAt: Date
└─ updatedAt: Date
```

**CloudKit sync:**
- Automatically enabled via `NSPersistentCloudKitContainer`
- No app code needed; Core Data handles sync transparently
- Conflicts resolved by "last write wins"
- Deletions propagate across devices automatically

---

## Data Flow

### User adds receipt photo

```
User selects photo
    ↓
ReceiptsView.onPhotosPicker()
    ↓
ProcessingController.process(image:)
    ↓
ProcessingController adds image to queue
    ↓
ProcessingController.processQueue() [async]
    ├─ ReceiptParser.parse(image) → Lambda
    │  └─ Lambda calls Claude Vision API → returns ReceiptData
    ├─ ReceiptStoreCore.saveReceipt(data)
    │  ├─ Create CachedReceipt entity
    │  ├─ Save to Core Data
    │  └─ CloudKit automatically syncs
    └─ Update UI with success/error
```

### User views receipts

```
ReceiptsView loads
    ↓
@FetchRequest loads receipts from Core Data
    ↓
UI displays CachedReceipt objects
    ↓
User taps to view details → ReceiptDetailView
```

### CloudKit sync happens silently

```
App saves to Core Data
    ↓
NSPersistentCloudKitContainer detects change
    ↓
Uploads to CloudKit (encrypted)
    ↓
Other user devices receive change via CloudKit
    ↓
Their Core Data automatically updates
```

---

## Security Model

### What's Protected

| Item | Where | How Protected | Risk if leaked |
|------|-------|---------------|---|
| Anthropic API key | Lambda env var | AWS Secrets Manager | Attacker can call Claude API on our dime |
| Anthropic API usage | Lambda | Server-side metrics | Can rate-limit, detect abuse |
| Receipt data | CloudKit | End-to-end encryption (iCloud) | User's personal data exposed |
| User identity | iCloud | CloudKit's user partition | Attacker sees other users' data |

### What's NOT Protected (By Design)

| Item | Why | Mitigation |
|------|-----|-----------|
| Lambda endpoint URL | Public; clients need it | Only accepts POST with valid image; returns 400 if parsing fails |
| Receipt existence | Stored in user's iCloud | Only visible to that user (CloudKit containers are per-user) |

### Pre-Commit Security Hook

All commits are scanned before they reach the repo:
```
.githooks/pre-commit
├─ Phase 1: Block credential patterns
│  ├─ *.tfstate files
│  ├─ *.zip files with secrets
│  ├─ ANTHROPIC_API_KEY = ...
│  └─ aws_secret_access_key = ...
└─ Phase 2: Run tests
   └─ Ensure code quality before merge
```

If a credential pattern is detected, commit is rejected. Prevents accidental exposure.

---

## Deployment

### App (iOS)

```
ReceiptVault/ (Xcode project)
├─ project.yml (xcodegen config)
├─ Sources/ (Swift code)
├─ Tests/ (unit tests)
└─ Derived from CI/CD (GitHub Actions, TestFlight, App Store)
```

**To deploy:**
1. Increment `MARKETING_VERSION` in `project.yml`
2. Run `xcodebuild ... build` to verify
3. Push to main (GitHub CI builds + ships to TestFlight/App Store)

### Backend (Lambda)

```
backend/
├─ lambda/ (Python/Node.js)
│  └─ handler.py (or index.js)
│     ├─ Parse event (base64 image)
│     ├─ Call Anthropic SDK
│     └─ Return ReceiptData JSON
└─ terraform/ (Infrastructure)
   ├─ main.tf (Lambda + API Gateway setup)
   ├─ terraform.tfvars (gitignored; prod values)
   └─ .terraform/ (gitignored; Terraform cache)
```

**To deploy:**
```bash
cd backend/terraform
terraform plan
terraform apply
```

---

## Future Considerations

### Potential Enhancements

1. **PDF Export**
   - Generate searchable PDF on Lambda
   - Email to user or store locally
   - Uses same Claude Vision extraction + wkhtmltopdf or Puppeteer

2. **Expense Categorization**
   - Lambda extracts category from shop name / receipt items
   - Store category in CachedReceipt
   - UI shows pie chart of spending by category

3. **Receipt Search**
   - Full-text search in Core Data (rawText field)
   - Filter by date range, shop, amount

4. **Offline Support**
   - Cache last 10 receipt photos locally
   - Parse when online
   - Queue management (already exists in ProcessingController)

5. **Analytics**
   - Log parsing requests to CloudWatch
   - Track user retention, avg receipts/user
   - Monitor Lambda error rates, cold starts

### What NOT to Build

- **User accounts:** Let iCloud handle it; no auth backend needed.
- **Real-time sharing:** Cross-user sharing would require moving data off iCloud; not a priority.
- **Client-side API keys:** Never. All keys server-side only.

---

## Testing

### Unit Tests

Located in `ReceiptVaultTests/`

```swift
// Test ReceiptParser with mock backend
MockReceiptParser: returns test ReceiptData

// Test ReceiptStoreCore with in-memory Core Data
TestDatabase: uses NSInMemoryStoreType

// Test ProcessingPipeline orchestration
MockParser + MockStore: verify calls in correct order
```

### Integration Tests

Run via pre-commit hook (before every commit):
```bash
xcodebuild -scheme ReceiptVault -destination '...' test
```

All tests must pass before commit is allowed.

---

## Troubleshooting

### "Commit blocked: Credential pattern detected"

**Cause:** Pre-commit hook found an API key or secret in staged files.

**Fix:**
1. Don't commit the file; move secret to AWS Secrets Manager / Lambda env vars
2. Or add filename to `.gitignore` if it should never be committed
3. Or pass `--no-verify` if you're sure it's safe (not recommended)

### Lambda returns 400: "Invalid image"

**Cause:** Image not valid JPEG, or base64 encoding failed.

**Fix:**
1. In ReceiptParser, check `jpegData` is not nil before base64 encoding
2. Test with a known-good image
3. Check Lambda logs in CloudWatch

### Receipt not syncing to other devices

**Cause:** CloudKit sync is broken or iCloud not configured.

**Fix:**
1. Verify user is signed into iCloud in device Settings
2. Check Core Data + CloudKit is enabled in project.yml
3. Verify CachedReceipt entity is cloud-enabled (should be automatic)
4. Look at CloudKit dashboard in developer.icloud.com

---

## Key Takeaways for New Developers

1. **The app is thin.** All business logic is in Lambda. Change parsing logic? Update Lambda, not the app.

2. **Credentials are server-side.** The app has no API keys. Ever. Pre-commit hook prevents this.

3. **CloudKit is the database.** No backend database needed. Core Data + CloudKit handles everything.

4. **Lambda is stateless.** Request in, ReceiptData out. No sessions, no user accounts, no state.

5. **Always run tests before committing.** Pre-commit hook runs `xcodebuild test`.

6. **Update this file when changing architecture.** Future agents depend on it being current.
