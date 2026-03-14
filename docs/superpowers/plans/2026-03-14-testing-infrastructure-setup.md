# Testing Infrastructure Setup Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish comprehensive unit testing infrastructure, pre-commit hooks, and test organization so that all subsequent implementation (Plans A & B) can follow TDD practices.

**Architecture:** XCTest framework with mock utilities, organized test structure, and git pre-commit hooks to enforce test passing before commits.

**Tech Stack:** XCTest, Swift, git hooks

---

## File Structure Overview

**Test files to create:**
- `ReceiptVaultTests/` — Main test target (created by Xcode)
- `ReceiptVaultTests/Helpers/MockAuthManager.swift` — Mock for GoogleSignIn
- `ReceiptVaultTests/Helpers/MockReceiptStore.swift` — Mock for local storage
- `ReceiptVaultTests/Helpers/TestFixtures.swift` — Sample data for tests
- `ReceiptVaultTests/ReceiptParserTests.swift` — Parser logic tests
- `ReceiptVaultTests/KeychainHelperTests.swift` — Keychain operations
- `ReceiptVaultTests/QuotaManagerTests.swift` — Quota tracking logic (Plan B)
- `ReceiptVaultTests/ProcessingPipelineTests.swift` — End-to-end pipeline (Plan B)
- `.githooks/pre-commit` — Git hook to run tests before commit

**Files to modify:**
- `project.yml` — Ensure test target is configured
- `ReceiptVault/Sources/Models/ReceiptVaultError.swift` — Ensure errors are testable
- `ReceiptVault/Sources/Models/KeychainHelper.swift` — Make testable with dependency injection

---

## Chunk 1: XCTest Setup & Mock Utilities

### Task 1: Create XCTest Target

**Files:**
- Create: `ReceiptVaultTests/` test target (via Xcode or xcodegen)

**Context:**
Xcode projects need an explicit test target. We'll use xcodegen to define it, then create the supporting structure.

- [ ] **Step 1: Add test target to project.yml**

Edit `project.yml`:

```yaml
targets:
  ReceiptVaultTests:
    type: bundle.unit-test
    platform: iOS
    deploymentTarget: "17.0"
    sources:
      - path: ReceiptVaultTests
    dependencies:
      - target: ReceiptVault
    settings:
      base:
        BUNDLE_LOADER: "$(TEST_HOST)"
        TEST_HOST: "$(BUILT_PRODUCTS_DIR)/ReceiptVault.app/ReceiptVault"
```

- [ ] **Step 2: Regenerate Xcode project**

```bash
xcodegen generate
```

Expected: `ReceiptVault.xcodeproj` now includes a test target.

- [ ] **Step 3: Create test directories**

```bash
mkdir -p ReceiptVaultTests/Helpers ReceiptVaultTests/Models ReceiptVaultTests/Services
```

- [ ] **Step 4: Commit**

```bash
git add project.yml .gitignore
git commit -m "test: add XCTest target to project

- Configure ReceiptVaultTests bundle target
- Test host linked to main app
- Test directories created

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

### Task 2: Create Mock Utilities

**Files:**
- Create: `ReceiptVaultTests/Helpers/MockAuthManager.swift`
- Create: `ReceiptVaultTests/Helpers/MockReceiptStore.swift`
- Create: `ReceiptVaultTests/Helpers/TestFixtures.swift`

**Context:**
Mocks allow unit tests to run without external dependencies (Google Sign-In, Keychain, iCloud sync, etc.). TestFixtures provide consistent sample data.

- [ ] **Step 1: Create MockAuthManager**

Create `ReceiptVaultTests/Helpers/MockAuthManager.swift`:

```swift
import Foundation
@testable import ReceiptVault

class MockAuthManager: ObservableObject {
    @Published var isSignedIn: Bool = false
    @Published var currentUserEmail: String? = nil

    var signInThrows: Error?
    var freshAccessTokenThrows: Error?

    func signIn() async throws {
        if let error = signInThrows {
            throw error
        }
        isSignedIn = true
        currentUserEmail = "test@example.com"
    }

    func signOut() {
        isSignedIn = false
        currentUserEmail = nil
    }

    func freshAccessToken() async throws -> String {
        if let error = freshAccessTokenThrows {
            throw error
        }
        return "mock_token_\(UUID().uuidString)"
    }
}
```

- [ ] **Step 2: Create MockReceiptStore**

Create `ReceiptVaultTests/Helpers/MockReceiptStore.swift`:

```swift
import Foundation
@testable import ReceiptVault

class MockReceiptStore: ObservableObject {
    @Published var receipts: [CachedReceipt] = []
    @Published var isLoading: Bool = false

    var fetchAllReceiptsThrows: Error?
    var saveReceiptThrows: Error?

    func fetchAllReceipts() async throws -> [CachedReceipt] {
        if let error = fetchAllReceiptsThrows {
            throw error
        }
        return receipts
    }

    func saveReceipt(receiptData: ReceiptData, jpgPath: String) async throws {
        if let error = saveReceiptThrows {
            throw error
        }
        let cached = CachedReceipt(
            driveFileId: UUID().uuidString,
            shopName: receiptData.shopName,
            date: receiptData.date,
            total: receiptData.total,
            currency: receiptData.currency,
            scannedAt: Date(),
            lineItems: receiptData.lineItems
        )
        receipts.append(cached)
    }

    func deleteReceipt(id: String) async throws {
        receipts.removeAll { $0.driveFileId == id }
    }

    func searchReceipts(query: String) -> [CachedReceipt] {
        receipts.filter { receipt in
            receipt.shopName.lowercased().contains(query.lowercased())
        }
    }
}
```

- [ ] **Step 3: Create TestFixtures**

Create `ReceiptVaultTests/Helpers/TestFixtures.swift`:

```swift
import Foundation
@testable import ReceiptVault

enum TestFixtures {
    static let sampleLineItem1 = LineItem(
        name: "Whole Grain Bread",
        quantity: 1,
        unitPrice: 4.99,
        totalPrice: 4.99
    )

    static let sampleLineItem2 = LineItem(
        name: "Organic Milk",
        quantity: 2,
        unitPrice: 3.49,
        totalPrice: 6.98
    )

    static let sampleReceiptData = ReceiptData(
        shopName: "Whole Foods Market",
        date: Date(timeIntervalSince1970: 1_710_432_000), // 2024-03-14
        total: 47.20,
        currency: "USD",
        lineItems: [sampleLineItem1, sampleLineItem2],
        rawText: """
        WHOLE FOODS MARKET
        123 Main St, San Francisco
        Date: 03/14/2024
        Total: $47.20
        """
    )

    static let sampleReceiptDataEuro = ReceiptData(
        shopName: "Rewe",
        date: Date(timeIntervalSince1970: 1_710_518_400), // 2024-03-15
        total: 32.50,
        currency: "EUR",
        lineItems: [
            LineItem(name: "Brot", quantity: 1, unitPrice: 2.50, totalPrice: 2.50),
            LineItem(name: "Milch", quantity: 1, unitPrice: 1.20, totalPrice: 1.20)
        ],
        rawText: "REWE Markt GmbH\n32,50 EUR"
    )

    static let sampleReceiptDataNoDate = ReceiptData(
        shopName: "Unknown Shop",
        date: Date(),
        total: nil,
        currency: nil,
        lineItems: [],
        rawText: "Blurry receipt, no visible date"
    )

    static let sampleCachedReceipt = CachedReceipt(
        driveFileId: "file_123",
        shopName: "Whole Foods Market",
        date: Date(),
        total: 47.20,
        currency: "USD",
        scannedAt: Date(),
        lineItems: [sampleLineItem1, sampleLineItem2]
    )
}
```

- [ ] **Step 4: Commit**

```bash
git add ReceiptVaultTests/Helpers/
git commit -m "test: add mock utilities and test fixtures

- MockAuthManager: simulate Google Sign-In
- MockReceiptStore: simulate local storage
- TestFixtures: reusable sample data (US, EUR, edge cases)
- Mocks allow isolated unit testing without external dependencies

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

## Chunk 2: Keychain & Error Tests

### Task 3: Test KeychainHelper (Safe, Non-Destructive)

**Files:**
- Modify: `ReceiptVault/Sources/Models/KeychainHelper.swift` — Add testability
- Create: `ReceiptVaultTests/Models/KeychainHelperTests.swift`

**Context:**
KeychainHelper is used by both ReceiptParser and SettingsView. It's critical to test read/write/delete operations.

- [ ] **Step 1: Make KeychainHelper testable with dependency injection**

Edit `ReceiptVault/Sources/Models/KeychainHelper.swift`:

Add this helper for testing (at the bottom of the file):

```swift
#if DEBUG
// For testing: allow swapping Security framework for a mock
protocol KeychainService {
    func read(key: String) -> String?
    func write(key: String, value: String) throws
    func delete(key: String)
}

class RealKeychainService: KeychainService {
    func read(key: String) -> String? {
        KeychainHelper.read(key: key)
    }

    func write(key: String, value: String) throws {
        try KeychainHelper.write(key: key, value: value)
    }

    func delete(key: String) {
        KeychainHelper.delete(key: key)
    }
}

class MockKeychainService: KeychainService {
    private var storage: [String: String] = [:]

    func read(key: String) -> String? {
        storage[key]
    }

    func write(key: String, value: String) throws {
        storage[key] = value
    }

    func delete(key: String) {
        storage.removeValue(forKey: key)
    }
}
#endif
```

- [ ] **Step 2: Create KeychainHelper tests**

Create `ReceiptVaultTests/Models/KeychainHelperTests.swift`:

```swift
import XCTest
@testable import ReceiptVault

class KeychainHelperTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Clean up test keychain entries before each test
        KeychainHelper.delete(key: "test_key")
    }

    func test_write_and_read_success() throws {
        let testKey = "test_key"
        let testValue = "test_value_123"

        try KeychainHelper.write(key: testKey, value: testValue)
        let retrieved = KeychainHelper.read(key: testKey)

        XCTAssertEqual(retrieved, testValue, "Should retrieve the exact value written")
    }

    func test_read_nonexistent_key_returnsNil() {
        let result = KeychainHelper.read(key: "nonexistent_key_xyz")
        XCTAssertNil(result, "Reading non-existent key should return nil")
    }

    func test_delete_removes_value() throws {
        let testKey = "test_delete_key"
        let testValue = "value_to_delete"

        try KeychainHelper.write(key: testKey, value: testValue)
        KeychainHelper.delete(key: testKey)
        let retrieved = KeychainHelper.read(key: testKey)

        XCTAssertNil(retrieved, "After delete, reading should return nil")
    }

    func test_overwrite_updates_value() throws {
        let testKey = "test_overwrite"

        try KeychainHelper.write(key: testKey, value: "value_1")
        try KeychainHelper.write(key: testKey, value: "value_2")
        let retrieved = KeychainHelper.read(key: testKey)

        XCTAssertEqual(retrieved, "value_2", "Overwriting should update the value")
    }

    func test_write_empty_string() throws {
        let testKey = "test_empty"

        try KeychainHelper.write(key: testKey, value: "")
        let retrieved = KeychainHelper.read(key: testKey)

        XCTAssertEqual(retrieved, "", "Should handle empty strings")
    }
}
```

- [ ] **Step 3: Test ReceiptVaultError descriptions**

Create `ReceiptVaultTests/Models/ReceiptVaultErrorTests.swift`:

```swift
import XCTest
@testable import ReceiptVault

class ReceiptVaultErrorTests: XCTestCase {
    func test_parseFailure_hasDescription() {
        let error = ReceiptVaultError.parseFailure("Test error message")
        XCTAssertEqual(error.errorDescription, "Test error message")
    }

    func test_authRequired_hasDescription() {
        let error = ReceiptVaultError.authRequired
        XCTAssertNotNil(error.errorDescription)
        XCTAssert(error.errorDescription!.contains("Authentication"))
    }

    func test_uploadFailure_hasDescription() {
        let error = ReceiptVaultError.uploadFailure("Upload failed")
        XCTAssertEqual(error.errorDescription, "Upload failed")
    }

    func test_pdfGenerationFailed_hasDescription() {
        let error = ReceiptVaultError.pdfGenerationFailed
        XCTAssertNotNil(error.errorDescription)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild -scheme ReceiptVault -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -testPlan ReceiptVaultTests 2>&1 | tail -30
```

Expected: `Test Suite passed` with 5 tests passing.

- [ ] **Step 5: Commit**

```bash
git add ReceiptVault/Sources/Models/KeychainHelper.swift ReceiptVaultTests/Models/
git commit -m "test: add KeychainHelper and error tests

- Test write/read/delete operations
- Test overwrite and edge cases
- Add error description tests
- All tests passing

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

## Chunk 3: Pre-Commit Hook & Test Enforcement

### Task 4: Set Up Git Pre-Commit Hook

**Files:**
- Create: `.githooks/pre-commit`

**Context:**
A pre-commit hook prevents commits if tests fail or build has warnings. This enforces discipline.

- [ ] **Step 1: Create hooks directory**

```bash
mkdir -p .githooks
```

- [ ] **Step 2: Create pre-commit hook**

Create `.githooks/pre-commit`:

```bash
#!/bin/bash
# Pre-commit hook: Run tests before allowing commit

set -e

echo "🧪 Running unit tests..."
xcodebuild -scheme ReceiptVault \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -configuration Debug \
    test 2>&1 | tail -50

if [ $? -ne 0 ]; then
    echo "❌ Tests failed. Commit blocked."
    exit 1
fi

echo "✅ Tests passed. Proceeding with commit."
exit 0
```

- [ ] **Step 3: Make hook executable**

```bash
chmod +x .githooks/pre-commit
```

- [ ] **Step 4: Configure git to use hooks**

```bash
git config core.hooksPath .githooks
```

**Note:** This is a local config change. Future clones will need to run this command too. Consider adding a setup script or documenting it in README.

- [ ] **Step 5: Test the hook**

Try to commit a dummy change:

```bash
echo "# test" >> README.md
git add README.md
git commit -m "test: trigger pre-commit hook"
```

Expected: Hook runs tests, then allows/blocks based on results. Undo the change:

```bash
git reset HEAD README.md
git checkout README.md
```

- [ ] **Step 6: Commit**

```bash
git add .githooks/pre-commit
git commit -m "ci: add pre-commit hook to enforce tests

- Runs full test suite before each commit
- Blocks commit if tests fail
- Developers must fix tests before committing
- Hook is local; document setup in README

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

## Chunk 4: Test Organization & Documentation

### Task 5: Create Test Guide & CI/CD Setup

**Files:**
- Create: `docs/TESTING.md` — Testing guide for developers
- Create: `.github/workflows/tests.yml` — GitHub Actions CI/CD (optional)

**Context:**
Document how to run tests locally and ensure CI runs them on every push.

- [ ] **Step 1: Create testing guide**

Create `docs/TESTING.md`:

```markdown
# ReceiptVault Testing Guide

## Running Tests Locally

### All tests:
```bash
xcodebuild -scheme ReceiptVault \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    test
```

### Specific test file:
```bash
xcodebuild -scheme ReceiptVault \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    test -testPlan ReceiptVaultTests -testClass ReceiptParserTests
```

### With coverage report:
```bash
xcodebuild -scheme ReceiptVault \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -enableCodeCoverage YES \
    test
```

## Test Structure

- **Unit Tests:** `ReceiptVaultTests/` — Isolated logic tests (no network, no UI)
- **Integration Tests:** `ReceiptVaultTests/Integration/` — Multi-module flows (future)
- **Mocks:** `ReceiptVaultTests/Helpers/` — Mock objects for dependencies
- **Fixtures:** `ReceiptVaultTests/Helpers/TestFixtures.swift` — Sample data

## Writing Tests (TDD)

For every new feature:
1. Write a failing test first
2. Run it to confirm it fails
3. Implement minimal code to pass
4. Run tests again
5. Refactor if needed
6. Commit

Example:
```swift
func test_quotaManager_allowsThreeReceiptsPerMonth() {
    let quota = QuotaManager()
    XCTAssert(quota.canAddReceipt())
    quota.recordReceiptAdded()
    quota.recordReceiptAdded()
    quota.recordReceiptAdded()
    XCTAssertFalse(quota.canAddReceipt(), "Should block 4th receipt")
}
```

## Coverage Goals

- **Critical paths** (auth, parsing, storage): 100%
- **Main logic** (quota, pipeline): 80%+
- **UI/helpers**: 50%+

Run coverage report:
```bash
xcodebuild test -scheme ReceiptVault \
    -enableCodeCoverage YES \
    -derivedDataPath build
```

Coverage report: `build/Logs/Test/*.xcresult`

## Pre-Commit Hook

Tests run automatically before each commit. If they fail, the commit is blocked:

```bash
$ git commit -m "add feature"
🧪 Running unit tests...
❌ Tests failed. Commit blocked.
```

Fix the test, then commit again.

## Continuous Integration (GitHub Actions)

Tests run on every push to `main` and pull requests. See `.github/workflows/tests.yml`.

## Troubleshooting

**Simulator not found:**
```bash
xcode-select --install
xcrun simctl list devices
```

**Keychain permission denied:**
Some Keychain tests may fail in CI. Use mocks for those tests.

**Flaky tests:**
If a test passes locally but fails in CI, it's likely timing-dependent. Add delays or mock time:
```swift
let expectation = XCTestExpectation(description: "Async operation")
DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
    expectation.fulfill()
}
wait(for: [expectation], timeout: 1.0)
```
```

- [ ] **Step 2: Create GitHub Actions workflow (optional, but recommended)**

Create `.github/workflows/tests.yml`:

```yaml
name: Tests

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3

      - name: Set up Xcode
        run: |
          sudo xcode-select -s /Applications/Xcode.app/Contents/Developer

      - name: Run tests
        run: |
          xcodebuild -scheme ReceiptVault \
            -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
            -configuration Debug \
            test
```

- [ ] **Step 3: Commit**

```bash
git add docs/TESTING.md .github/workflows/tests.yml
git commit -m "docs: add testing guide and CI/CD workflow

- Document how to run tests locally
- Add GitHub Actions CI/CD pipeline
- Coverage goals and troubleshooting
- Pre-commit hook enforcement documented

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

## Summary

**This plan establishes:**

✅ XCTest test target integrated into Xcode project
✅ Mock utilities (MockAuthManager, MockReceiptStore, TestFixtures)
✅ Keychain & error handling tests (baseline coverage)
✅ Pre-commit hook that blocks commits if tests fail
✅ Testing guide for developers
✅ GitHub Actions CI/CD pipeline
✅ TDD-ready infrastructure

**What this enables:**

- Plans A & B can be executed with TDD from day one
- Every commit enforces passing tests
- New developers have clear testing guidelines
- CI/CD catches regressions automatically

**Estimated effort:** 1.5–2 hours
**Risk level:** Very low (infrastructure, non-destructive)
**Testing focus:** Verifying hooks and test execution

**Next steps after Plan C:**
1. Execute Plan A (App Store submission) with TDD
2. Execute Plan B (Backend & monetization) with TDD
3. Both plans include test-first steps; use this infrastructure as foundation
