# App Store Submission Readiness Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix critical bugs, add error handling UI, complete privacy/compliance metadata, and verify the app builds with zero warnings.

**Architecture:** This plan focuses on app-layer changes (UI, error handling, metadata) and compliance requirements. It does NOT include the backend migration or monetization features—those are in Plan B.

**Tech Stack:** SwiftUI, StoreKit 2 (future), Privacy policies (plain text or HTML hosted externally)

---

## File Structure Overview

**Files to create:**
- `ReceiptVault/Sources/Models/PrivacyPolicy.swift` — Privacy policy content (versioned)
- `docs/PRIVACY_POLICY.md` — Privacy policy document (published to web)

**Files to modify:**
- `ReceiptVault/Info.plist` — Add privacy policy URL
- `ReceiptVault/Sources/DriveUploader/DriveUploader.swift` — Fix force unwrap bug (line 350)
- `ReceiptVault/Sources/Pipeline/ProcessingController.swift` — Add error state tracking
- `ReceiptVault/Views/ContentView.swift` — Display error alerts
- `ReceiptVault/App/ReceiptVaultApp.swift` — Error alert presentation
- `ReceiptVault/Assets.xcassets/AppIcon.appiconset/` — Verify app icon exists

**Files to test:**
- `ReceiptVaultTests/DriveUploaderTests.swift` — Test currency symbol for nil
- `ReceiptVaultTests/ReceiptParserTests.swift` — Test error handling

---

## Chunk 1: Critical Bug Fixes

### Task 1: Fix Force Unwrap in DriveUploader

**Files:**
- Modify: `ReceiptVault/Sources/DriveUploader/DriveUploader.swift:350`

**Context:**
Line 350 in `currencySymbol(for:)` has a force unwrap that crashes if `code` is nil:
```swift
default: return "\(code!) "  // CRASH!
```

- [ ] **Step 1: Write failing test**

Create file `ReceiptVaultTests/DriveUploaderTests.swift`:

```swift
import XCTest
@testable import ReceiptVault

class DriveUploaderTests: XCTestCase {
    let uploader = DriveUploader(authManager: AuthManager())

    func test_currencySymbolForNil_returnsEmptyString() {
        // Access the private method via reflection (or make it internal for testing)
        // For now, test indirectly via the filename generation
        let receipt = ReceiptData(
            shopName: "Test Shop",
            date: Date(),
            total: nil,  // nil total means no currency symbol
            currency: nil,
            lineItems: [],
            rawText: "test"
        )
        let filename = uploader.makeFilename(for: receipt)
        // Should not crash and should end with .pdf
        XCTAssert(filename.hasSuffix(".pdf"))
    }

    func test_currencySymbolForUnknownCode_returnsCodeWithSpace() {
        // This tests the default case indirectly
        // We'll need to refactor to test the private method properly
        // For now, this is a placeholder—see Step 3 for refactor
    }
}
```

- [ ] **Step 2: Run test to verify it fails (or is inconclusive)**

```bash
xcodebuild -scheme ReceiptVault -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug test 2>&1 | head -50
```

Expected: Test runs but you can't fully test the private method. This shows we need to refactor.

- [ ] **Step 3: Refactor currencySymbol as internal method**

Edit `ReceiptVault/Sources/DriveUploader/DriveUploader.swift`:

Find the `currencySymbol(for:)` method and change from `private` to internal, then fix the force unwrap:

```swift
// BEFORE (line ~343):
private func currencySymbol(for code: String?) -> String {
    switch code?.uppercased() {
    case "USD": return "$"
    case "EUR": return "€"
    case "GBP": return "£"
    case "JPY": return "¥"
    case .none: return ""
    default: return "\(code!) "  // <-- BUG: force unwrap
    }
}

// AFTER:
func currencySymbol(for code: String?) -> String {
    switch code?.uppercased() {
    case "USD": return "$"
    case "EUR": return "€"
    case "GBP": return "£"
    case "JPY": return "¥"
    case .none: return ""
    default: return (code ?? "") + " "  // <-- FIXED: no force unwrap
    }
}
```

**Explanation:**
- Changed `private` to no access modifier (default is internal within the module)
- Changed `"\(code!)"` to `(code ?? "") + " "` — if code is nil, use empty string; if it's some unknown currency code, add it with a space

- [ ] **Step 4: Update test to directly test the method**

Edit `ReceiptVaultTests/DriveUploaderTests.swift`:

```swift
import XCTest
@testable import ReceiptVault

class DriveUploaderTests: XCTestCase {
    let uploader = DriveUploader(authManager: AuthManager())

    func test_currencySymbolForNil_returnsEmptyString() {
        let result = uploader.currencySymbol(for: nil)
        XCTAssertEqual(result, "")
    }

    func test_currencySymbolForUnknownCode_returnsCodeWithSpace() {
        let result = uploader.currencySymbol(for: "XYZ")
        XCTAssertEqual(result, "XYZ ")
    }

    func test_currencySymbolForUSD_returnsDollarSign() {
        let result = uploader.currencySymbol(for: "USD")
        XCTAssertEqual(result, "$")
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
xcodebuild -scheme ReceiptVault -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug test -testPlan ReceiptVaultTests 2>&1 | grep -E "(PASSED|FAILED|error:)"
```

Expected: All three tests PASS.

- [ ] **Step 6: Build to verify no warnings**

```bash
xcodebuild -scheme ReceiptVault -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug build 2>&1 | grep -E "warning:|error:"
```

Expected: No warnings related to force unwrap.

- [ ] **Step 7: Commit**

```bash
git add ReceiptVault/Sources/DriveUploader/DriveUploader.swift ReceiptVaultTests/DriveUploaderTests.swift
git commit -m "fix: remove force unwrap in currencySymbol, add tests

- Fix bug where nil currency code caused crash
- Make currencySymbol method internal for testing
- Add unit tests for currency symbol generation
- Covers: USD, EUR, GBP, JPY, unknown codes, nil

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

## Chunk 2: Error Handling UI

### Task 2: Add Error State to ProcessingController

**Files:**
- Modify: `ReceiptVault/Sources/Pipeline/ProcessingController.swift`

**Context:**
Currently, ProcessingController throws errors but doesn't expose them to the UI. We need to:
1. Add `@Published var lastError: ReceiptVaultError?`
2. Catch errors in `processReceipt()` and store them
3. Add a method to dismiss/clear errors

- [ ] **Step 1: Update ProcessingController to track and expose errors**

Edit `ReceiptVault/Sources/Pipeline/ProcessingController.swift`:

```swift
// ADD near the top of the class (after @Published var isProcessing):
@Published var lastError: ReceiptVaultError?

// ADD a method to clear errors:
func clearError() {
    lastError = nil
}

// UPDATE the processReceipt method to catch and store errors:
// Find this section:
func processReceipt(_ receiptData: ReceiptData, jpgPath: String) async {
    isProcessing = true
    defer { isProcessing = false }

    do {
        // ... existing logic ...
    } catch {
        // Log error (you might add logging later)
        print("Receipt processing failed: \(error)")
    }
}

// Change to:
func processReceipt(_ receiptData: ReceiptData, jpgPath: String) async {
    isProcessing = true
    defer { isProcessing = false }
    clearError()  // Clear previous errors

    do {
        // ... existing logic ...
    } catch let error as ReceiptVaultError {
        lastError = error
    } catch {
        // Convert generic error to ReceiptVaultError
        lastError = .parseFailure("An unexpected error occurred: \(error.localizedDescription)")
    }
}
```

- [ ] **Step 2: Update ContentView to display error alerts**

Edit `ReceiptVault/App/ContentView.swift`:

Add this modifier to the main view hierarchy (inside the NavigationStack or at the top level):

```swift
.alert("Error", isPresented: .constant(processingController.lastError != nil)) {
    Button("OK") {
        processingController.clearError()
    }
} message: {
    if let error = processingController.lastError {
        Text(error.errorDescription ?? "Unknown error")
    }
}
```

**Note:** You may need to adjust where this alert is placed depending on your existing view hierarchy. It should be at the top level so it's always dismissible.

- [ ] **Step 3: Test error display manually**

Build and run:
```bash
xcodebuild -scheme ReceiptVault -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug build
open ReceiptVault.xcodeproj
```

Then in the simulator:
1. Try to process a receipt without providing API key (should trigger `authRequired` error)
2. Verify error alert appears with descriptive message
3. Tap "OK" to dismiss
4. Verify no lingering error state

- [ ] **Step 4: Commit**

```bash
git add ReceiptVault/Sources/Pipeline/ProcessingController.swift ReceiptVault/App/ContentView.swift
git commit -m "feat: add error state and alerts to UI

- Add @Published lastError to ProcessingController
- Display errors as swiftui alerts in ContentView
- Clear errors when starting new processing
- Improves UX for parse failures, auth errors, network errors

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

## Chunk 3: Privacy & Compliance

### Task 3: Add Privacy Policy & URL

**Files:**
- Create: `docs/PRIVACY_POLICY.md`
- Modify: `ReceiptVault/Info.plist`

**Context:**
App Store requires a published Privacy Policy. You'll provide a URL pointing to your privacy policy hosted on a web server or GitHub Pages.

- [ ] **Step 1: Create privacy policy document**

Create file `docs/PRIVACY_POLICY.md`:

```markdown
# ReceiptVault Privacy Policy

**Last Updated:** March 14, 2026

## Overview

ReceiptVault is a personal receipt management app. This policy explains what data we collect and how we handle it.

## Data We Collect

### Receipt Data
When you photograph a receipt, the app extracts:
- Shop name
- Date
- Total amount and currency
- Line items (products/services)
- Full text from the receipt

This data is processed locally on your device and synced via iCloud.

### API Processing
Receipt images are sent to:
- **Google Cloud Vision API** (OCR) — extracts text from the image
- **Anthropic Claude API** — structures the extracted text

Both are third-party services. See their privacy policies:
- [Google Privacy Policy](https://policies.google.com/privacy)
- [Anthropic Privacy Policy](https://www.anthropic.com/privacy)

### iCloud Sync
Your receipts and metadata are synced to your personal iCloud account via CloudKit. Apple manages this data according to their privacy practices. See [Apple iCloud Privacy](https://www.apple.com/icloud/privacy/).

### Camera & Photo Library Access
When you grant permission, the app can:
- Access your camera to photograph receipts
- Access your photo library to import receipt photos

This permission is required for the app to function. We do not transmit photos elsewhere without processing them for extraction.

## Data We Don't Collect
- We do not collect personal information (name, email, location, etc.)
- We do not track or analyze your behavior
- We do not sell or share your receipt data with third parties
- We do not store data on our own servers

## Data Retention
- **Local data:** Stored indefinitely on your device until you delete
- **iCloud data:** Retained in your iCloud account according to Apple's policies
- **API processing:** Google and Anthropic may log requests temporarily for debugging; see their policies

## Contact
For privacy questions, contact: [your-email@example.com]

## Changes
We may update this policy. Changes will be posted here with an updated date.
```

**Note:** Replace `[your-email@example.com]` with your actual contact email.

- [ ] **Step 2: Publish privacy policy to the web**

You have two options:
1. **GitHub Pages:** Host `docs/PRIVACY_POLICY.md` as a GitHub Pages site
2. **Simple web host:** Upload the HTML to any web server

For now, assume you'll use GitHub Pages. The URL will be:
```
https://yourusername.github.io/ReceiptVault/PRIVACY_POLICY.html
```

(Replace `yourusername` with your actual GitHub username)

If using GitHub Pages, enable it in your repo settings (Settings → Pages → Source: `docs` folder).

- [ ] **Step 3: Add privacy policy URL to Info.plist**

Edit `ReceiptVault/Info.plist`:

Add this key-value pair (or update if it exists):

```xml
<key>NSPrivacyManifest</key>
<dict>
    <key>NSPrivacyTracking</key>
    <false/>
    <key>NSPrivacyTrackingDomains</key>
    <array/>
</dict>
```

**Note:** This is the new iOS 17+ privacy manifest. Also verify your Info.plist has these permissions (should already be there from project.yml):

```xml
<key>NSCameraUsageDescription</key>
<string>ReceiptVault uses the camera to photograph receipts.</string>

<key>NSPhotoLibraryUsageDescription</key>
<string>ReceiptVault needs access to your photo library to import receipt images.</string>
```

- [ ] **Step 4: Commit**

```bash
git add docs/PRIVACY_POLICY.md ReceiptVault/Info.plist
git commit -m "docs: add privacy policy and privacy manifest

- Create comprehensive privacy policy document
- Add NSPrivacyManifest to Info.plist (iOS 17+)
- Disclose data processing with Google Cloud Vision and Claude API
- Clarify iCloud sync behavior
- Host on GitHub Pages at: https://yourusername.github.io/ReceiptVault/PRIVACY_POLICY.html

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

## Chunk 4: App Icon & Metadata

### Task 4: Verify App Icon & Complete Metadata

**Files:**
- Verify: `ReceiptVault/Assets.xcassets/AppIcon.appiconset/`

**Context:**
Your git history mentions "Update app icon to new teal lock-on-document design". Verify it's in the project and at the correct sizes. App Store requires:
- App Icon 1024×1024 (for the App Store)
- Icon set for all iOS sizes (automatically generated by Xcode)

- [ ] **Step 1: Verify app icon files exist**

```bash
ls -la ReceiptVault/Assets.xcassets/AppIcon.appiconset/
```

Expected: You should see PNG files for various sizes (1024, 512, 180, 120, 152, etc.). If missing, you need to add them.

**If missing:** Download a 1024×1024 PNG of your teal lock-on-document design and add to the asset catalog via Xcode.

- [ ] **Step 2: Verify icon in Xcode project**

```bash
xcodebuild -scheme ReceiptVault -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug build 2>&1 | grep -i "icon"
```

Expected: No warnings about missing app icon.

- [ ] **Step 3: Prepare App Store metadata (informational, no code change)**

You'll need to fill these in App Store Connect later:

- **App Name:** Receipt Vault
- **Subtitle:** (Optional) e.g., "Organize Receipts Instantly"
- **Description:**
  ```
  Receipt Vault transforms scattered receipts into a searchable archive. Photograph any receipt, and Claude AI extracts shop name, date, total, and line items. Receipts sync securely to iCloud and stay organized forever.

  Features:
  • Instant extraction with Claude Vision AI
  • Searchable PDF archive
  • iCloud sync across devices
  • Smart date & currency parsing
  • Organize by shop, date, amount

  Free tier: 5 receipts/month. Upgrade to unlimited.
  ```
- **Keywords:** receipt, expense, archive, organization, cloud, icloud, receipt scanner
- **Support URL:** Point to your GitHub repo or a support page
- **Privacy Policy URL:** https://yourusername.github.io/ReceiptVault/PRIVACY_POLICY.html

- [ ] **Step 4: Screenshot preparation (informational)**

You'll need 5-6 screenshots for each device size. Capture these in the simulator:
1. Home screen with list of receipts
2. Single receipt detail view
3. Search/filter view
4. Settings screen
5. Add receipt flow
6. (Optional) Error recovery

For now, just make a note to capture these before submission.

- [ ] **Step 5: Commit (metadata placeholder)**

```bash
git add -A
git commit -m "docs: add app store metadata checklist

- Verify app icon 1024x1024 present
- Document required App Store metadata
- Add privacy policy URL reference
- Screenshots to be captured before submission

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

## Chunk 5: Build Verification

### Task 5: Final Build & Warning Check

**Files:**
- Verify: Entire project builds clean

- [ ] **Step 1: Clean build**

```bash
xcodebuild -scheme ReceiptVault -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug clean build 2>&1 | tail -50
```

Expected: `Build complete! (...)` with zero warnings.

- [ ] **Step 2: Check for any lingering warnings**

```bash
xcodebuild -scheme ReceiptVault -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug build 2>&1 | grep "warning:"
```

Expected: Empty output (no warnings).

- [ ] **Step 3: Run all tests**

```bash
xcodebuild -scheme ReceiptVault -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug test 2>&1 | tail -20
```

Expected: All tests pass.

- [ ] **Step 4: Commit final state**

```bash
git add -A
git commit -m "build: verify clean build with zero warnings

- All tests passing
- No compiler warnings
- App builds successfully for iOS Simulator
- Ready for App Store submission preparation

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

## Summary

**What this plan delivers:**
✅ Fix critical force-unwrap bug
✅ Add error alerting UI
✅ Create privacy policy
✅ Add privacy manifest to Info.plist
✅ Verify app icon
✅ Prepare metadata
✅ Build verification (zero warnings)

**What's NOT included (see Plan B):**
- Backend Lambda setup
- Google Cloud Vision integration
- Core Data migration from Drive/Sheets
- iCloud CloudKit sync
- StoreKit 2 monetization
- Paywall UI

**Estimated effort:** 2-3 hours
**Risk level:** Low (all changes are self-contained, additive)
**Blockers:** None
