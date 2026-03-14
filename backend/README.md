# ReceiptVault Backend

AWS Lambda-based receipt parsing service.

## Architecture

- **Lambda Function:** Receives receipt image, calls Google Cloud Vision OCR, then Claude API for structured extraction
- **API Gateway:** HTTP endpoint (POST /parse-receipt)
- **Input:** Base64-encoded JPEG receipt image
- **Output:** Structured ReceiptData JSON

## Deployment

### Prerequisites
- AWS CLI configured with credentials
- Terraform 1.0+
- Node.js 20+
- Google Cloud service account key (for Vision API)
- Anthropic API key

### Steps

1. **Prepare environment variables** (`terraform/terraform.tfvars`):
   ```
   anthropic_api_key = "sk-..."
   gcp_project_id = "your-project-id"
   ```

2. **Build Lambda package**:
   ```bash
   cd backend/lambda
   ./deploy.sh
   ```

3. **Deploy with Terraform**:
   ```bash
   cd ../terraform
   terraform init
   terraform plan
   terraform apply
   ```

4. **Get API endpoint**:
   ```bash
   terraform output api_endpoint
   ```

### API Usage

**Endpoint:** `POST {api_endpoint}/parse-receipt`

**Request:**
```json
{
  "imageBase64": "base64-encoded-jpeg-data",
  "userId": "optional-user-id"
}
```

**Response:**
```json
{
  "shopName": "Whole Foods",
  "date": "2025-03-14",
  "total": 47.20,
  "currency": "USD",
  "lineItems": [
    {
      "name": "Organic Milk",
      "quantity": 2,
      "unitPrice": 3.49,
      "totalPrice": 6.98
    }
  ],
  "rawText": "full OCR text"
}
```

## Cost Estimation

- **Google Cloud Vision:** ~$0.0015 per image
- **Claude API:** ~$0.0001 per extraction (text-only is cheap)
- **AWS Lambda:** ~$0.0005 per request
- **Total per receipt:** ~$0.002

At 2,000 receipts/month (100 users × 20 receipts): ~$4/month

## Monitoring

Lambda logs are in CloudWatch. Monitor:
- Invocation errors
- Duration (should be <30s)
- Memory usage (512MB allocated)
