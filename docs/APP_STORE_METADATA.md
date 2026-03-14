# Receipt Vault — App Store Metadata Checklist

## Overview
This document contains all required metadata for App Store Connect submission. Fill these in during the submission process.

---

## Basic App Information

### App Name
**Receipt Vault**

### Subtitle (Optional)
**Organize Receipts Instantly**

---

## Description

### Full Description
```
Receipt Vault transforms scattered receipts into a searchable archive. Photograph any receipt, and Claude AI extracts shop name, date, total, and line items. Receipts sync securely to iCloud and stay organized forever.

Features:
• Instant extraction with Claude Vision AI
• Searchable PDF archive
• iCloud sync across devices
• Smart date & currency parsing
• Organize by shop, date, amount

Free tier: 3 receipts/month. Upgrade to unlimited.
```

---

## Keywords
```
receipt, expense, archive, organization, cloud, icloud, receipt scanner
```

---

## Support & Legal URLs

### Support URL
Update this before submission with your actual support page:
```
https://github.com/yourusername/ReceiptVault
```

### Privacy Policy URL
Update this before submission. Host on your own domain:
```
https://yourusername.github.io/ReceiptVault/PRIVACY_POLICY.html
```

**Note:** A privacy policy template is available at `/Users/eric/code/ReceiptVault/docs/PRIVACY_POLICY.md`

### Terms of Service URL (Optional)
Only required if you have a backend or subscriptions:
```
https://yourusername.github.io/ReceiptVault/TERMS_OF_SERVICE.html
```

---

## Screenshots (Required)

### Device Sizes Needed
- **iPhone 6.7"** (5-6 screenshots)
- **iPad 12.9"** (optional, recommended for feature visibility)

### Screenshot Checklist
Capture the following screens in the simulator to highlight key features:

- [ ] **Screenshot 1: Home Screen**
  - Show receipt list with multiple entries
  - Highlight visual design and app branding

- [ ] **Screenshot 2: Receipt Detail View**
  - Show extracted data (shop name, date, total, line items)
  - Highlight rich content display

- [ ] **Screenshot 3: Search/Filter View**
  - Show filtering by shop name, date range, or amount
  - Demonstrate discoverability

- [ ] **Screenshot 4: Add Receipt Flow**
  - Show camera or photo library picker
  - Highlight simple, intuitive UI

- [ ] **Screenshot 5: Settings/Preferences**
  - Show account, storage, and subscription settings
  - Demonstrate app customization

- [ ] **Screenshot 6: iCloud Sync Status (Optional)**
  - Show sync status or multi-device messaging
  - Demonstrate cloud features

### Screenshot Tips
1. Capture in **Xcode Simulator** with:
   - `Product → Scheme → Edit Scheme → Run → Arguments Passed On Launch`
   - Set `UITESTING=YES` to show demo data if needed
2. Use **Preview Screenshots** app or manual `Cmd + S` in Simulator
3. Resize to correct resolution before upload
4. Add optional text overlays in post-processing to highlight features

---

## App Category
**Productivity** or **Utilities**

---

## Content Rating Questionnaire
Typical answers for Receipt Vault:
- **Violence:** None
- **Sexual Content:** None
- **Profanity:** None
- **Gambling:** None
- **Alcohol/Tobacco:** None
- **Unfiltered Web:** No

---

## Minimum Requirements
- **Minimum iOS Version:** 17.0
- **Device Families:** iPhone, iPad (if supporting iPad)
- **Languages:** English

---

## Submission Checklist

### Pre-Submission
- [ ] App Icon (1024×1024 PNG) verified in Xcode
- [ ] Build passes without warnings: `xcodebuild -scheme ReceiptVault -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug build`
- [ ] Privacy Policy URL is live and accessible
- [ ] Support/contact method is valid
- [ ] App runs on iOS 17.0 simulator without crashes
- [ ] Screenshots are high-quality and accurately represent features

### In App Store Connect
- [ ] Update app name and subtitle
- [ ] Paste full description
- [ ] Add keywords
- [ ] Set category
- [ ] Upload app icon (1024×1024)
- [ ] Add 5-6 localized screenshots
- [ ] Fill content rating questionnaire
- [ ] Add support and privacy policy URLs
- [ ] Review promotional text (optional)
- [ ] Set age rating (likely 4+)
- [ ] Build uploaded and tested
- [ ] Submit for review

---

## Version History Notes
For first submission (version 1.0):
```
Receipt Vault is launching with:
• AI-powered receipt extraction via Claude Vision
• Secure Google Drive integration for PDF storage
• Automatic Google Sheets indexing
• Multi-device iCloud sync
• Free tier: 3 receipts/month

Come organize your receipts!
```

---

## Notes
- The Claude API key is stored securely in the iOS Keychain; users are never exposed to API details.
- The Google OAuth flow is handled via the GoogleSignIn SDK; credentials are not stored in the app.
- Receipts are stored on the user's own Google Drive; the app does not retain copies on a backend server.

---

**Last Updated:** 2026-03-14
