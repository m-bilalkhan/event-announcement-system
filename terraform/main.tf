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
# IAM - Assuming role for Lambda execution
#----------------------------
resource "aws_iam_role" "this" {
  name               = "lambda_subscribe_role"
  assume_role_policy = data.aws_iam_policy_document.this.json
  tags = {
    ProjectName = var.ProjectName
  }
}

#----------------------------
# IAM - Attach required managed policy - Basic Lambda Execution
#----------------------------
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

#----------------------------
# IAM - Attach required managed policy - SNS Full Access
#----------------------------
resource "aws_iam_role_policy_attachment" "lambda_sns_access" {
  role       = aws_iam_role.this.name
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
# Lambda - Function
#----------------------------
resource "aws_lambda_function" "this" {
  filename         = data.archive_file.this.output_path
  function_name    = "SubscribeToSNSFunction"
  role             = aws_iam_role.this.arn
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