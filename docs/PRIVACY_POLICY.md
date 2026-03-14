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
