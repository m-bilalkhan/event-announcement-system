data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
variable "ProjectName" {
  default = "Event-Announcement-System"
}

#----------------------------
# S3 - Create an S3 bucket to store event announcements
#----------------------------
resource "aws_s3_bucket" "this" {
  bucket = "event-announcement-system-bucket"
  tags = {
    Name = "Event Announcement System Bucket"
    ProjectName = var.ProjectName
  }
}

#----------------------------
# S3 - Configure bucket ownership controls
#----------------------------
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

#----------------------------
# S3 - Create an S3 bucket to host the static website
#----------------------------
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = false
  restrict_public_buckets = false
}

#----------------------------
# S3 - Set bucket policy to allow public read access for website hosting
#----------------------------
resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.this.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadForWebsiteContent"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.this.arn}/*"
      }
    ]
  })
}

#----------------------------
# S3 - Configure the S3 bucket for website hosting
#----------------------------
resource "aws_s3_bucket_website_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

#----------------------------
# SNS - Create an SNS topic for event announcements
#----------------------------
resource "aws_sns_topic" "this" {
  name = "event-announcements-topic"
  tags = {
    ProjectName = var.ProjectName
  }
}

#----------------------------
# IAM - Creating policy for Lambda role
#----------------------------
data "aws_iam_policy_document" "this" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

#----------------------------
# IAM - Subscriber - Assuming role for Lambda execution
#----------------------------
resource "aws_iam_role" "subscriber" {
  name               = "lambda_subscribe_role"
  assume_role_policy = data.aws_iam_policy_document.this.json
  tags = {
    ProjectName = var.ProjectName
  }
}

#----------------------------
# IAM - Subscriber - Attach required managed policy - Basic Lambda Execution
#----------------------------
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.subscriber.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

#----------------------------
# IAM - Subscriber - Attach required managed policy - SNS Full Access
#----------------------------
resource "aws_iam_role_policy_attachment" "lambda_sns_access" {
  role       = aws_iam_role.subscriber.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSNSFullAccess"
}

#----------------------------
# Packing the Lambda function code
#----------------------------
data "archive_file" "this" {
  type        = "zip"
  source_file = "../backend/subscriber_function.py"
  output_path = "${path.module}/lambda/function.zip"
}

#----------------------------
# Lambda - Subscriber - Function
#----------------------------
resource "aws_lambda_function" "subscriber-function" {
  filename         = data.archive_file.this.output_path
  function_name    = "SubscribeToSNSFunction"
  role             = aws_iam_role.subscriber.arn
  handler          = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.this.output_base64sha256
  publish          = true
  timeout          = 20

  runtime = "python3.13"

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.this.arn
    }
  }

  tags = {
    ProjectName = var.ProjectName
  }
}

#----------------------------
# Lambda - API Gateway Invoke Permission
#----------------------------
resource "aws_lambda_permission" "allow_apigw" {
  depends_on    = [aws_apigatewayv2_api.this]
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.subscriber-function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:ap-south-1:${data.aws_caller_identity.current.account_id}:${aws_apigatewayv2_api.this.id}/*"
}

#----------------------------
# IAM - Publisher - Assuming role for Lambda execution
#----------------------------
resource "aws_iam_role" "publisher" {
  name               = "lambda_publisher_role"
  assume_role_policy = data.aws_iam_policy_document.this.json
  tags = {
    ProjectName = var.ProjectName
  }
}

#----------------------------
# IAM - Publisher - Attach required managed policy - Basic Lambda Execution
#----------------------------
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.publisher.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

#----------------------------
# IAM - Publisher - Attach required managed policy - SNS Full Access
#----------------------------
resource "aws_iam_role_policy_attachment" "lambda_sns_access" {
  role       = aws_iam_role.publisher.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSNSFullAccess"
}

#----------------------------
# IAM - Publisher - Attach required managed policy - SNS Full Access
#----------------------------
resource "aws_iam_role_policy_attachment" "lambda_s3_access" {
  role       = aws_iam_role.publisher.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

#----------------------------
# Packing the Lambda function code
#----------------------------
data "archive_file" "pub" {
  type        = "zip"
  source_file = "../backend/publisher_function.py"
  output_path = "${path.module}/lambda/function.zip"
}

#----------------------------
# Lambda - Publisher - Function
#----------------------------
resource "aws_lambda_function" "publisher-function" {
  filename         = data.archive_file.pub.output_path
  function_name    = "PublishToSNSFunction"
  role             = aws_iam_role.publisher.arn
  handler          = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.pub.output_base64sha256
  publish          = true
  timeout          = 20

  runtime = "python3.13"

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.this.arn
      S3_BUCKET_NAME = aws_s3_bucket.this.bucket
    }
  }

  tags = {
    ProjectName = var.ProjectName
  }
}

#----------------------------
# Lambda - API Gateway Invoke Permission
#----------------------------
resource "aws_lambda_permission" "allow_apigw" {
  depends_on    = [aws_apigatewayv2_api.this]
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.publisher-function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:ap-south-1:${data.aws_caller_identity.current.account_id}:${aws_apigatewayv2_api.this.id}/*"
}

#----------------------------
# API Gateway
#----------------------------
resource "aws_apigatewayv2_api" "this" {
  name          = "EventManagementAPI"
  protocol_type = "HTTP"
  description = "API Gateway for Event Announcement System"
  tags = {
    ProjectName = var.ProjectName
  }
}

#----------------------------
# API Gateway - Integration for Subscriber Lambda
#----------------------------
resource "aws_apigatewayv2_integration" "subscriber_integration" {
  api_id             = aws_apigatewayv2_api.this.id
  integration_type = "AWS_PROXY"

  integration_method        = "POST"
  integration_uri           = aws_lambda_function.subscriber-function.invoke_arn  
}

#----------------------------
# API Gateway - Route for Publisher Lambda
#----------------------------
resource "aws_apigatewayv2_integration" "publisher_integration" {
  api_id             = aws_apigatewayv2_api.this.id
  integration_type = "AWS_PROXY"

  integration_method        = "POST"
  integration_uri           = aws_lambda_function.publisher-function.invoke_arn  
}

#----------------------------
# API Gateway - Route for Subscriber Lambda
#----------------------------
resource "aws_apigatewayv2_route" "subscriber_route" {
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "POST /subscribe-event"
  target    = "integrations/${aws_apigatewayv2_integration.subscriber_integration.id}"
} 

#----------------------------
# API Gateway - Route for Publisher Lambda
#----------------------------
resource "aws_apigatewayv2_route" "publisher_route" {
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "POST /publish-event"
  target    = "integrations/${aws_apigatewayv2_integration.publisher_integration.id}"
} 

#----------------------------
# API Gateway - Staging
#----------------------------
resource "aws_apigatewayv2_stage" "this" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true
}
