terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-north-1"
}


resource "aws_dynamodb_table" "resume_stats" {
  name         = "cloud-resume-stats"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}
# Python zip
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/lambda_function.py"
  output_path = "${path.module}/lambda/lambda_function.zip"
}

# .IAM 
resource "aws_iam_role" "lambda_exec_role" {
  name = "cloud-resume-lambda-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

#  DynamoDB 
resource "aws_iam_role_policy_attachment" "lambda_dynamodb" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

#cloudWatch
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda define function
resource "aws_lambda_function" "counter_lambda" {
  function_name    = "cloud-resume-counter"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
}
# ----------------------------------------------------
# Layer 3: REST API Gateway Configuration
# ----------------------------------------------------

# 1. Create the REST API
resource "aws_api_gateway_rest_api" "resume_api" {
  name        = "cloud-resume-api"
  description = "Public API Gateway for the Cloud Resume visitor counter"
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# 2. Define the GET method on the root path (/)
resource "aws_api_gateway_method" "get_method" {
  rest_api_id   = aws_api_gateway_rest_api.resume_api.id
  resource_id   = aws_api_gateway_rest_api.resume_api.root_resource_id
  http_method   = "GET"
  authorization = "NONE"
}

# 3. Integrate GET method with the Lambda function via Lambda Proxy Integration
resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.resume_api.id
  resource_id             = aws_api_gateway_rest_api.resume_api.root_resource_id
  http_method             = aws_api_gateway_method.get_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.counter_lambda.invoke_arn
}

# 4. Grant permission for API Gateway to invoke the Lambda function
resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.counter_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.resume_api.execution_arn}/*/*"
}

# 5. Deploy the API and set up the 'prod' stage
resource "aws_api_gateway_deployment" "api_deployment" {
  depends_on  = [aws_api_gateway_integration.lambda_integration]
  rest_api_id = aws_api_gateway_rest_api.resume_api.id
}

resource "aws_api_gateway_stage" "prod_stage" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.resume_api.id
  stage_name    = "prod"
}

# 6. Output the public API Gateway Invoke URL upon completion
output "api_url" {
  value       = "${aws_api_gateway_stage.prod_stage.invoke_url}/"
  description = "The public API Gateway URL to read and update visitor count"
}

# ----------------------------------------------------
# Layer 3: S3 Bucket Configuration for Static Website
# ----------------------------------------------------

# 1. Manage the existing S3 bucket
resource "aws_s3_bucket" "website_bucket" {
  bucket = "shani-cloud-resume-2026"
}

# 2. Block all direct public access (traffic served via CloudFront OAC only)
resource "aws_s3_bucket_public_access_block" "website_bucket_block" {
  bucket = aws_s3_bucket.website_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
