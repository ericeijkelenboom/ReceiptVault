# ReceiptVault

An iOS app for scanning and managing receipts with intelligent extraction, local storage, and cloud sync.

---

## Quick Start

**For new developers:**
1. Read [CLAUDE.md](./CLAUDE.md) — project rules and immediate setup
2. Read [docs/superpowers/architecture.md](./docs/superpowers/architecture.md) — how the system works
3. Set up your environment (see _Development Setup_ below)
4. Follow the workflow in [CLAUDE.md § Build & Commit](./CLAUDE.md)

**First-time agent context:** This is NOT the original Google Drive/Sheets design. Architecture redesign (Mar 2026) moved to server-side credentials (Lambda) and local storage (Core Data + CloudKit). See [architectural decisions](./docs/superpowers/architecture.md) for rationale.

---

## What ReceiptVault Does

Users photograph receipts with their iPhone. The app:
1. Sends the image to a Lambda backend (no credentials in app)
2. Backend uses Claude Vision API to extract structured data (shop, date, total, items)
3. App stores receipt data locally in Core Data
4. Automatically syncs across user's devices via iCloud + CloudKit
5. User can search, organize, and view receipt details in the app

**Key design principle:** The app is thin (UI + local storage only). All business logic and credentials live on the backend.

---

## Architecture at a Glance

```
┌─────────────────────────────────────────┐
│          iOS App                         │
│  ┌──────────────────────────────────┐  │
│  │ UI Layer (SwiftUI Views)         │  │
│  │ - ReceiptsView                   │  │
│  │ - ReceiptDetailView              │  │
│  │ - SettingsView                   │  │
│  └──────────────────────────────────┘  │
│              ↓                           │
│  ┌──────────────────────────────────┐  │
│  │ ProcessingController             │  │
│  │ (state machine, queue, progress) │  │
│  └──────────────────────────────────┘  │
│              ↓                           │
│  ┌──────────────────────────────────┐  │
│  │ ProcessingPipeline               │  │
│  │ (orchestrate image→data flow)    │  │
│  └──────────────────────────────────┘  │
│         ↓                      ↓        │
│    ReceiptParser        ReceiptStoreCore│
│         ↓                      ↓        │
└─────────────────────────────────────────┘
         ↓                      ↓
    HTTP to Lambda         Core Data + CloudKit
         ↓                      ↓
    ┌────────────┐        ┌────────────┐
    │   Lambda   │        │   iCloud   │
    │ - Parse    │        │ - Backup   │
    │ - Validate │        │ - Sync     │
    │ - Claude   │        │ - Restore  │
    │   Vision   │        └────────────┘
    └────────────┘
```

### Active Modules

**ReceiptParser** — Wrapper around HTTP calls to Lambda. Sends base64-encoded image, receives `ReceiptData` struct. No credentials in this module.

**ProcessingPipeline** — Orchestrates image → parsed data → local storage. Calls `ReceiptParser` and `ReceiptStoreCore` in sequence.

**ProcessingController** — App-level state machine. Manages processing queue, progress updates, error handling, and quota tracking.

**ReceiptStoreCore** — Core Data persistence + CloudKit sync. All receipt data lives here. Automatically syncs across user's devices.

**Config** — Non-secret configuration (API endpoint URL, timeouts, etc.).

### Why This Design?

- **No app credentials:** Even if app is compromised, no API keys to steal.
- **Can rotate keys on backend:** No app update needed.
- **Automatic sync:** CloudKit handles cross-device sync invisibly.
- **Zero backend database:** Data lives in user's iCloud, not on our servers.
- **No user accounts:** Leverages existing iCloud identity.

See [architectural decisions](./docs/superpowers/architecture.md) for full rationale.

---

## Development Setup

### Prerequisites
- Xcode 16+
- iOS 17.0+ simulator (iPhone 17 Pro preferred)
- xcodegen 2.44.1: `brew install xcodegen`
- GitHub CLI: `gh auth login`

### Initial Setup

1. **Clone the repository**
   ```bash
   git clone <repo-url>
   cd ReceiptVault
   ```

2. **Set up local config** (secrets)
   ```bash
   # Create Config.xcconfig (gitignored, not in repo)
   cat > Config.xcconfig << 'EOF'
   LAMBDA_ENDPOINT = https://your-lambda-url.example.com
   EOF
   ```

3. **Generate Xcode project**
   ```bash
   xcodegen generate
   ```

4. **Open in Xcode**
   ```bash
   open ReceiptVault.xcodeproj
   ```

5. **Configure signing** (in Xcode)
   - Select project in navigator
   - Select "ReceiptVault" target
   - Signing & Capabilities tab
   - Set Development Team (your Apple ID team)

### Dependency Notes

- **No third-party dependencies** — uses only Apple frameworks (SwiftUI, Core Data, CloudKit, URLSession)
- **No Google SDK** — backend handles all credential management
- **No Anthropic SDK** — app delegates to Lambda for Claude API calls

---

## Workflow

### Before You Code

Always follow this order:

1. **Read the code** — understand what you're changing
2. **Write a test** that fails (if adding feature) — see _Testing_ below
3. **Make the test pass** — implement the minimal change
4. **Build and verify** — `xcodebuild ... build`
5. **Commit** — pre-commit hook runs security + tests automatically

### Build Before Commit

```bash
cd /Users/eric/code/ReceiptVault
xcodebuild \
  -scheme ReceiptVault \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug \
  build
```

**If it fails:** Fix all errors and warnings before committing. The pre-commit hook will block commits with build failures.

### xcodegen Rules

- **RUN** `xcodegen generate` when: adding/deleting a Swift file, or editing `project.yml`
- **DO NOT** run when: only editing code in existing files
- After running, **always commit the changes:**
  ```bash
  git add project.yml ReceiptVault.xcodeproj
  git commit -m "chore: regenerate Xcode project"
  ```

### Commit Message Format

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>: <subject>

<body (optional)>

<footer (optional)>
```

Types: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `perf`, `security`

Example:
```bash
git commit -m "feat: add receipt search by shop name

Adds case-insensitive search to ReceiptsView. Also updates
ReceiptStoreCore.grouped() to support partial matches.

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

### Git Push

```bash
git push origin main
```

Or with credential helper:
```bash
git -c credential.helper='!/opt/homebrew/bin/gh auth git-credential' push origin main
```

---

## Code Structure

```
ReceiptVault/
├── App/                            # App entry point
│   └── ReceiptVaultApp.swift
├── Sources/
│   ├── Models/                     # Data structures
│   │   ├── ReceiptData.swift
│   │   ├── LineItem.swift
│   │   ├── CachedReceipt.swift
│   │   └── ReceiptVaultError.swift
│   ├── ReceiptParser/              # Backend HTTP wrapper
│   │   └── ReceiptParser.swift
│   ├── Pipeline/                   # Orchestration
│   │   ├── ProcessingPipeline.swift
│   │   └── ProcessingController.swift
│   ├── Storage/                    # Core Data + CloudKit
│   │   └── ReceiptStoreCore.swift
│   └── Config.swift                # Non-secret config
├── Views/                          # SwiftUI UI
│   ├── ReceiptsView.swift
│   ├── ReceiptDetailView.swift
│   └── SettingsView.swift
├── Resources/
│   ├── Localizable.strings
│   └── Assets.xcassets
├── Tests/                          # Unit tests
│   └── ReceiptParserTests.swift
├── ShareExtension/                 # Home Screen widget
│   └── ShareViewController.swift
├── project.yml                     # xcodegen config
├── ReceiptVault.xcodeproj          # (Generated, don't edit)
└── CLAUDE.md                       # Project rules
```

---

## Data Model

```swift
struct ReceiptData: Codable {
    let shopName: String           // e.g. "Whole Foods"
    let date: Date                 // receipt date
    let total: Decimal?            // e.g. 47.20
    let currency: String?          // e.g. "USD"
    let lineItems: [LineItem]      // items on receipt
    let rawText: String            // full OCR text
}

struct LineItem: Codable {
    let name: String
    let quantity: Decimal?
    let unitPrice: Decimal?
    let totalPrice: Decimal?
}

// Stored in Core Data as CachedReceipt
struct CachedReceipt {
    let id: UUID
    let shopName: String
    let date: Date
    let total: NSDecimalNumber?
    let currency: String?
    let lineItems: [LineItem]  // stored as JSON
    let rawText: String
    let driveFileId: String    // CloudKit record ID
    let createdAt: Date
    let updatedAt: Date
}
```

---

## Testing

### Running Tests

```bash
xcodebuild \
  -scheme ReceiptVault \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug \
  test
```

The pre-commit hook runs these tests automatically before allowing commits.

### Writing Tests

Follow TDD: write the failing test first, then implement.

Example:
```swift
import XCTest

class ReceiptParserTests: XCTestCase {
    func test_parse_extractsShopName() async throws {
        let image = UIImage(named: "test-receipt.jpg")!
        let parser = ReceiptParser()

        let data = try await parser.parse(image: image)

        XCTAssertEqual(data.shopName, "Whole Foods")
    }
}
```

### Test Guidelines

- Test only public interfaces (don't test private methods)
- Mock external dependencies (HTTP calls, storage)
- Test error cases: malformed responses, network failures, etc.
- Aim for >80% coverage of critical paths

---

## Security

### Credentials Handling

**Rule:** All secrets are server-side only. The app has zero credentials.

- Anthropic API key: stored in Lambda environment variables (AWS Secrets Manager)
- Lambda endpoint: stored in `Config.xcconfig` (not a secret, just a URL)
- CloudKit: uses iCloud identity (no credentials needed)

**Never:**
- Commit API keys or credentials to git
- Hardcode credentials in code
- Store credentials in app bundle
- Bypass the pre-commit hook with `--no-verify`

The pre-commit hook scans for credential patterns before every commit. If it blocks you:
1. Remove the credential from the file
2. Move it to Lambda environment variables or AWS Secrets Manager
3. Stage the fixed file and commit again

See [security incident response](./docs/superpowers/architecture.md#security-incident) for more details.

### Pre-Commit Hook

The `.githooks/pre-commit` hook runs on every commit:

1. **Phase 1: Security scan** — blocks commits with credential patterns or sensitive files
2. **Phase 2: Test suite** — runs all tests

If either phase fails, the commit is blocked. Fix the issue and try again.

---

## Deployment

### iOS App

1. Bump version in `project.yml` under `Info.plist.version`
2. Build for distribution:
   ```bash
   xcodebuild -scheme ReceiptVault -configuration Release archive
   ```
3. Upload to TestFlight or App Store via Xcode

### Lambda Backend

The Lambda function receives images and returns parsed data. It's separate from this repository.

Endpoint: `POST /parse-receipt` with JSON body:
```json
{
  "image": "base64-encoded-jpeg"
}
```

Response:
```json
{
  "shopName": "Whole Foods",
  "date": "2025-03-15T00:00:00Z",
  "total": 47.20,
  "currency": "USD",
  "lineItems": [...],
  "rawText": "..."
}
```

---

## Architecture Documentation

For detailed explanation of architectural decisions:

- [CLAUDE.md](./CLAUDE.md) — project rules and immediate setup
- [docs/superpowers/architecture.md](./docs/superpowers/architecture.md) — system design, decisions, rationale
- [.claude/projects/...memory/](./docs/superpowers/architecture.md#architectural-decisions) — architectural decisions, module structure, security incident response

Key decision: all credentials server-side, zero in app. This prevents compromise even if app is reverse-engineered.

---

## Common Tasks

### Add a New Field to Receipt Data

1. Update `ReceiptData` struct in `Models/ReceiptData.swift`
2. Update `CachedReceipt` Core Data entity in `Storage/ReceiptStoreCore.swift`
3. Update `ReceiptStoreCore.saveReceipt()` to handle the new field
4. Update Lambda to return the new field
5. Write tests for the new extraction logic
6. Commit: `git commit -m "feat: add receipt field 'FOO'"`

### Fix a Bug in Receipt Parsing

1. Write a test that reproduces the bug
2. Verify it fails: `xcodebuild ... test`
3. Fix the code in `ReceiptParser.swift` or `ProcessingPipeline.swift`
4. Verify test passes
5. Commit: `git commit -m "fix: handle FOO edge case in receipt parsing"`

### Optimize a Slow Operation

1. Identify the bottleneck (profiler, logs)
2. Write a performance test: `func test_parse_performance() { measure { ... } }`
3. Optimize the code
4. Verify test passes and improvement is measurable
5. Commit: `git commit -m "perf: cache FOO to improve parse time by 50%"`

---

## Troubleshooting

### Build fails: "ReceiptVault.xcodeproj not found"

**Fix:** Run `xcodegen generate`

### Tests timeout

**Cause:** Lambda endpoint is slow or unreachable

**Fix:** Mock Lambda responses in tests. Don't rely on real network calls during local development.

### CloudKit sync not working

**Cause:** iCloud sign-in not enabled in Simulator

**Fix:** Simulator → Settings → sign in with Apple ID

### App crashes with "No such module 'CloudKit'"

**Fix:** Ensure `project.yml` includes CloudKit capability. Run `xcodegen generate`.

---

## Roadmap

**Completed:**
- Core receipt extraction via Claude Vision
- Local storage with Core Data + CloudKit sync
- Receipt search and organization
- Multi-device sync via iCloud

**Future:**
- Export receipts as PDF
- Receipt categorization (groceries, gas, etc.)
- Receipt sharing with other users
- Advanced reporting and analytics
- Widget for quick receipt access

See [architecture decisions](./docs/superpowers/architecture.md#future-considerations) for design implications of future features.

---

## Contributing

1. Follow the workflow in [CLAUDE.md](./CLAUDE.md)
2. Write tests for new features
3. Build and test locally before pushing
4. Create a pull request with clear description
5. Ensure all tests pass before merging

---

## License

[Add your license here]

---

## Contact

[Add contact info for project lead/team]

---

## Quick Links

- **[CLAUDE.md](./CLAUDE.md)** — Rules and immediate setup
- **[Architecture Decisions](./docs/superpowers/architecture.md)** — Why we made these choices
- **[Build & Commit Rules](./docs/superpowers/architecture.md#build-before-commit)** — Workflow
- **[Module Structure](./docs/superpowers/architecture.md#active-modules)** — How modules work together
- **[Security & Credentials](./docs/superpowers/architecture.md#security)** — How we keep secrets safe
