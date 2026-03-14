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
