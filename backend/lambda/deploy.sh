#!/bin/bash
set -e

echo "📦 Preparing Lambda package..."
cd "$(dirname "$0")"

# Install dependencies
npm install

# Create deployment package
zip -r lambda-function.zip . -x "node_modules/aws-sdk/*"

# Move to terraform directory
mv lambda-function.zip ../terraform/

echo "✅ Lambda package ready at backend/terraform/lambda-function.zip"
echo ""
echo "Next steps:"
echo "1. Set environment variables in terraform/terraform.tfvars:"
echo "   anthropic_api_key = \"your-api-key\""
echo "   gcp_project_id = \"your-project-id\""
echo ""
echo "2. Deploy with Terraform:"
echo "   cd terraform"
echo "   terraform init"
echo "   terraform plan"
echo "   terraform apply"
echo ""
echo "3. Note the API endpoint from terraform output"
