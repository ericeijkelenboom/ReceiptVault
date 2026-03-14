# ReceiptVault Hybrid Monetization & Backend Design

**Date:** 2026-03-14
**Status:** Ready for Implementation
**Target User:** Personal finance enthusiasts

---

## Overview

ReceiptVault transforms scattered receipts (physical + digital) into a searchable, organized archive. Users photograph receipts; the app extracts structured data (shop, date, total, currency, line items), generates searchable PDFs, and syncs everything via iCloud.

The hybrid monetization model uses a free tier (5 receipts/month) to drive conversions to paid tiers ($0.99/mo unlimited or $4.99 permanent unlock). The backend uses a two-stage OCR + extraction pipeline (Google Cloud Vision for OCR, Claude for structured parsing) to reduce API costs by ~67%.

---

## 1. Monetization Model

### Free Tier (3 receipts/month)
- Upload receipts via camera or photo library
- Full-featured search (shop name, date range, amount, text content from receipt)
- iCloud sync across all devices (iPhone, iPad, Mac)
- Local archive, organized by date
- All premium features accessible on the 3 free receipts (users experience the full product)

**Rationale:** Tighter limit creates faster conversion pressure while still allowing users to experience the product. Access to all features on free receipts prevents artificial restrictions that would frustrate users.

### Paid Tier: Subscription ($0.99/month)
- Unlimited receipts/month
- Everything from free tier
- Auto-renews monthly; can cancel anytime

**Rationale:** Low price point ($12/year) targets personal users who want one tool they love, not an expensive expense-tracking platform.

### Paid Tier: One-Time Purchase ($4.99 one-time)
- Permanent unlimited receipts (no monthly renewal)
- Labeled: "Support Development + Permanent Unlimited"

**Rationale:** Appeals to users who prefer one-time purchases or want to "support the developer." Generates revenue from power users willing to pay a premium. Serves as a psychological alternative to subscription.

### Paywall & Quota Reset
- **Monthly reset:** Calendar month (Jan 1–31, etc.)
- **Trigger:** After uploading 3rd receipt in a calendar month, friendly banner appears: "You've used your 3 free receipts this month. Upgrade to add more."
- **Display:** Home screen shows remaining quota ("1 of 3 receipts used")
- **Behavior:** Free users can still search, view, and manage their 3 receipts; they just can't add more until the next month or they upgrade

---

## 2. Architecture Overview

### App Layer (iOS, existing ReceiptParser signature unchanged)

**Before:**
```swift
func parse(image: UIImage) async throws -> ReceiptData
// Direct call to Anthropic API from device
```

**After:**
```swift
func parse(image: UIImage) async throws -> ReceiptData
// POSTs image to YOUR_LAMBDA_URL/parse-receipt
// Lambda handles OCR + extraction
// Returns structured ReceiptData
```

**Key:** Public API is identical. Only internals change. Existing callers (UI, pipeline) are unaffected.

### Backend Layer (AWS Lambda + API Gateway)

**Endpoint:** `POST /parse-receipt`

**Input:**
```json
{
  "imageBase64": "base64-encoded JPEG",
  "userId": "optional, for tracking/rate-limiting"
}
```

**Pipeline:**
1. **Google Cloud Vision OCR** → Extract raw text from image
   - Cost: ~$0.0015 per image
   - Handles: skewed receipts, small text, multiple languages
   - Output: Raw text string

2. **Claude API (text only)** → Structure extraction
   - Input: OCR text + extraction prompts (your existing prompts from ReceiptParser)
   - Output: Structured JSON (shop name, date, total, currency, line items, raw text)
   - Cost: ~$0.0001 per call (text is much cheaper than vision)

**Output:**
```json
{
  "shopName": "Whole Foods",
  "date": "2025-03-14",
  "total": 47.20,
  "currency": "EUR",
  "lineItems": [...],
  "rawText": "full OCR text"
}
```

**Error Handling:**
- Vision fails → 400 Bad Request ("Invalid or unreadable receipt image")
- Claude fails → 500 Internal Server Error (retry on device)
- Rate limit hit → 429 Too Many Requests (user tries again later)

### Local Storage (iOS)

**Core Data schema:**
- **Receipt entity:** id (UUID), shopName (String), date (Date), total (Decimal), currency (String), rawText (String), jpgPath (String), createdAt (Date), quotaMonth (String, for tracking monthly reset)
- **LineItem entity:** id (UUID), receiptId (UUID, foreign key), name (String), quantity (Decimal?), unitPrice (Decimal?), totalPrice (Decimal?)
- **Synced via iCloud CloudKit:** Automatic cross-device sync (iPhone ↔ iPad ↔ Mac)

**Removed:**
- Google Drive integration (DriveUploader module)
- Google Sheets index (SheetsLogger module)
- Manifest.json files

### Authentication & Security

**API Keys:**
- **Anthropic API key:** Lives on Lambda server only (never exposed to device)
- **Google Cloud Vision credentials:** Managed via IAM service account on Lambda
- **iCloud sync:** Handled by CloudKit (encrypted, Apple-managed)

**Rate Limiting:**
- Optional: Track usage per userId on Lambda (future: enforce quotas at API level)
- Current: Quotas enforced on device (monthly reset, 5-free check)

---

## 3. Data Flow

### Upload & Parse Flow
```
User photographs receipt
           ↓
iOS app sends JPEG to Lambda /parse-receipt
           ↓
Lambda: Google Cloud Vision extracts OCR text
           ↓
Lambda: Claude structures OCR text → ReceiptData JSON
           ↓
Lambda returns JSON to iOS app
           ↓
iOS app saves to local Core Data
           ↓
iCloud CloudKit syncs to other devices (transparent)
           ↓
Complete (no Drive/Sheets involvement)
```

### Search & Retrieval Flow
```
User searches "Whole Foods"
           ↓
iOS app queries local Core Data
           ↓
Results displayed instantly (no network needed)
           ↓
iCloud keeps device cache in sync with other devices
```

---

## 4. Feature Matrix

| Feature | Free (3/mo) | Paid Sub | Paid One-Time |
|---------|-------------|----------|---------------|
| Upload receipts | 3/month | Unlimited | Unlimited |
| Search (shop, date, amount, text) | ✓ | ✓ | ✓ |
| iCloud sync | ✓ | ✓ | ✓ |
| PDF generation | ✓ | ✓ | ✓ |
| Export PDF | ✓ | ✓ | ✓ |
| Offline access | ✓ | ✓ | ✓ |
| Monthly reset | ✓ (rolls over) | N/A | N/A |

---

## 5. Cost Analysis

### API Costs (per receipt)
| Component | Cost |
|-----------|------|
| Google Cloud Vision OCR | ~$0.0015 |
| Claude text extraction | ~$0.0001 |
| Lambda + API Gateway overhead | ~$0.0005 |
| **Total per receipt** | **~$0.002** |

**Comparison to current Vision-only:** ~67% reduction ($0.006 → $0.002)

### Monthly Infrastructure (100 users, 20 receipts/user/month = 2,000 calls/month)
| Component | Cost |
|-----------|------|
| API calls (2,000 × $0.002) | ~$4/mo |
| Lambda (compute + requests) | ~$3-5/mo |
| API Gateway | ~$1-2/mo |
| CloudKit (iCloud sync) | Free (bundled with Apple) |
| **Total infrastructure** | **~$10-15/mo** |

### Unit Economics
- Revenue (10 paying users @ $0.99/mo): $10/mo
- Break-even point: ~16 paid subscribers
- Margin: Positive at 20+ paid subscribers

---

## 6. User Journey

### Onboarding
1. User opens app
2. Settings screen prompts for Claude API key (existing flow) — **deprecated after backend launch**
3. First screen: "Add your first receipt"

### Free Tier Limit Experience
1. User uploads 3rd receipt in January
2. 4th upload triggers banner: "You've used your 3 free receipts this month. Upgrade to add more."
3. Two CTAs: "Subscribe $0.99/mo" or "Unlock Permanently $4.99"
4. User can still search, view, and manage their 3 receipts
5. February 1st: Quota resets; user can add 3 more free receipts

### Conversion Triggers
- **Subscription:** User wants unlimited access but prefers flexibility (monthly renewal)
- **One-time purchase:** User wants permanent unlock or wants to "support the developer"
- **Retry next month:** User closes banner, waits for quota reset (shows app is useful enough to return to)

---

## 7. Implementation Roadmap (High Level)

**Phase 1: Backend Setup**
- Create Lambda function for `/parse-receipt` endpoint
- Integrate Google Cloud Vision (existing project)
- Integrate Claude API
- Error handling and logging

**Phase 2: ReceiptParser Refactor**
- Update `parse(image:)` to POST to Lambda instead of direct Claude call
- Remove direct Anthropic API code
- Update error handling

**Phase 3: Storage Migration**
- Migrate from Google Drive + Sheets → Core Data + iCloud
- Remove DriveUploader and SheetsLogger modules
- Implement Core Data schema and CloudKit sync

**Phase 4: Monetization UI**
- Implement receipt quota tracking
- Add paywall banner
- Wire up StoreKit 2 for subscriptions and one-time purchases

**Phase 5: App Store Submission**
- Privacy policy
- App icon, screenshots, preview
- Complete Age Rating questionnaire
- Fix all warnings and crashes

---

## 8. Risk & Mitigation

| Risk | Mitigation |
|------|-----------|
| Lambda cold start delays parsing | Use provisioned concurrency or SQS queue (async) |
| Google Cloud Vision fails on blurry images | Graceful error, user can retake photo |
| Claude extraction unpredictable | Validate output; add fallback heuristics |
| User hits free quota on day 5 of month | Design friction is intentional; user retries month later or upgrades |
| iCloud sync conflicts | CloudKit handles conflicts automatically; user sees most recent version |
| Backend costs exceed revenue | Monitor costs closely; optimize prompts or increase prices |

---

## 9. Success Metrics

- **Conversion rate:** % of free users who upgrade (target: 2-5%)
- **Average revenue per user (ARPU):** (subscription revenue + one-time purchases) / active users
- **Retention:** % of users who return after 1 week, 1 month
- **API cost per user:** Track to ensure profitability threshold
- **User satisfaction:** App Store rating (target: ≥4.5 stars)

---

## 10. Future Extensions (Out of Scope)

- CSV/Sheets export (users can manually export their data)
- Expense categorization and analytics
- Team/shared receipts (not for personal finance enthusiasts)
- Standalone web dashboard
- Integration with tax software

---

## Appendix: Key Decisions

1. **iCloud over Google Drive:** Simpler, more native to iOS, eliminates fragility of user-visible Drive structure
2. **Two-stage OCR + Claude over Vision-only:** ~67% cost reduction while maintaining extraction quality
3. **5 receipts/month free tier:** High enough to build habit, low enough to trigger conversion quickly
4. **$0.99/mo + $4.99 one-time:** Diversifies revenue; offers both subscription and one-time options
5. **Personal finance enthusiasts as target:** Clear, underserved market; high product affinity; willing to pay for tools they love
