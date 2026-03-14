terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Lambda execution role
resource "aws_iam_role" "lambda_role" {
  name = "receipt-vault-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# Attach basic execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda function
resource "aws_lambda_function" "parse_receipt" {
  filename      = "lambda-function.zip"
  function_name = "receipt-vault-parse-receipt"
  role          = aws_iam_role.lambda_role.arn
  handler       = "parse-receipt.handler"
  runtime       = "nodejs20.x"
  timeout       = 60
  memory_size   = 512

  environment {
    variables = {
      ANTHROPIC_API_KEY          = var.anthropic_api_key
      GOOGLE_APPLICATION_CREDENTIALS = var.google_credentials_path
      GCP_PROJECT_ID             = var.gcp_project_id
    }
  }
}

# API Gateway
resource "aws_apigatewayv2_api" "receipt_api" {
  name          = "receipt-vault-api"
  protocol_type = "HTTP"
  target        = aws_lambda_function.parse_receipt.arn
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.parse_receipt.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.receipt_api.execution_arn}/*/*"
}

# Outputs
output "api_endpoint" {
  value = aws_apigatewayv2_api.receipt_api.api_endpoint
}

output "lambda_function_name" {
  value = aws_lambda_function.parse_receipt.function_name
}
