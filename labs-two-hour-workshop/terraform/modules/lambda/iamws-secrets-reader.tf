# ═══════════════════════════════════════════════════════════════════════════
# EXERCISE 5: Secrets Reader (credential-access via Lambda environment variables)
# ═══════════════════════════════════════════════════════════════════════════
# Attack: lambda:GetFunctionConfiguration exposes secrets stored in env vars
# Path: Reader → GetFunctionConfiguration → Read plaintext secrets → Access external systems
# Category: credential-access (pathfinding.cloud)
# Root Cause: Secrets stored in Lambda env vars instead of Secrets Manager
# Defense: Use Secrets Manager with proper IAM permissions

# ─────────────────────────────────────────────────────────────────────────────
# THE TARGET: A Lambda function with secrets in environment variables (bad practice)
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_iam_role" "iamws-app-lambda-role" {
  name = "iamws-app-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "iamws-app-lambda-role-logs" {
  role       = aws_iam_role.iamws-app-lambda-role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "archive_file" "app_lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/app_lambda.zip"
  source {
    content  = <<-EOF
      import os
      import json
      def handler(event, context):
          # In real code, this would use the secrets to connect to a database
          # NEVER do this - use Secrets Manager instead!
          return {
              'statusCode': 200,
              'body': json.dumps('App running with database connection')
          }
    EOF
    filename = "lambda_function.py"
  }
}

resource "aws_lambda_function" "iamws-app-with-secrets" {
  filename         = data.archive_file.app_lambda_zip.output_path
  function_name    = "iamws-app-with-secrets"
  role             = aws_iam_role.iamws-app-lambda-role.arn
  handler          = "lambda_function.handler"
  runtime          = "python3.11"
  source_code_hash = data.archive_file.app_lambda_zip.output_base64sha256
  timeout          = 30

  # ═══════════════════════════════════════════════════════════════════════════
  # ROOT CAUSE: Secrets stored in plaintext environment variables!
  #
  # Anyone with lambda:GetFunctionConfiguration can read these values.
  # This is a common misconfiguration - developers store secrets here
  # because it's convenient, not realizing they're exposed.
  #
  # THE FIX: Use AWS Secrets Manager:
  # 1. Store secrets in Secrets Manager
  # 2. Grant Lambda role secretsmanager:GetSecretValue for specific secret ARNs
  # 3. Retrieve secrets at runtime in the Lambda code
  # ═══════════════════════════════════════════════════════════════════════════
  environment {
    variables = {
      DB_HOST           = "prod-db.example.internal"
      DB_USERNAME       = "app_service_account"
      DB_PASSWORD       = "SuperSecretPassword123!"
      API_KEY           = "sk-prod-api-key-do-not-expose"
      ADMIN_CREDENTIALS = "admin:P@ssw0rd!"
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# THE ATTACKER: A user who can read Lambda configurations
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_iam_policy" "iamws-secrets-reader-policy" {
  name        = "iamws-secrets-reader-policy"
  description = "Can read Lambda configurations - exposes env var secrets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowLambdaRead"
      Effect = "Allow"
      Action = [
        "lambda:GetFunction",
        "lambda:GetFunctionConfiguration",
        "lambda:ListFunctions"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_user" "iamws-secrets-reader-user" {
  name = "iamws-secrets-reader-user"
  path = "/"
}

resource "aws_iam_access_key" "iamws-secrets-reader-user" {
  user = aws_iam_user.iamws-secrets-reader-user.name
}

resource "aws_iam_user_policy_attachment" "iamws-secrets-reader-user-attach" {
  user       = aws_iam_user.iamws-secrets-reader-user.name
  policy_arn = aws_iam_policy.iamws-secrets-reader-policy.arn
}

# Also create a role version for flexibility in the lab
resource "aws_iam_role" "iamws-secrets-reader-role" {
  name = "iamws-secrets-reader-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { AWS = var.aws_assume_role_arn }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "iamws-secrets-reader-role-attach" {
  role       = aws_iam_role.iamws-secrets-reader-role.name
  policy_arn = aws_iam_policy.iamws-secrets-reader-policy.arn
}
