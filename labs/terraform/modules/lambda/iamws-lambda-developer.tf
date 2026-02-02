# ═══════════════════════════════════════════════════════════════════════════
# EXERCISE 4: Lambda Developer (existing-passrole via UpdateFunctionCode)
# ═══════════════════════════════════════════════════════════════════════════
# Attack: lambda:UpdateFunctionCode allows modifying a Lambda with a privileged role
# Path: Developer → UpdateFunctionCode → Replace code with credential exfiltration → Invoke → Admin
# Category: existing-passrole (pathfinding.cloud)
# Root Cause: Can modify ANY Lambda function, including those with privileged roles
# Defense: Resource constraint (specific Lambda ARN in identity policy)

# ─────────────────────────────────────────────────────────────────────────────
# THE TARGET: A Lambda function with a privileged execution role
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_iam_role" "iamws-privileged-lambda-role" {
  name = "iamws-privileged-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "iamws-privileged-lambda-role-admin" {
  role       = aws_iam_role.iamws-privileged-lambda-role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Basic Lambda logging permissions
resource "aws_iam_role_policy_attachment" "iamws-privileged-lambda-role-logs" {
  role       = aws_iam_role.iamws-privileged-lambda-role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Create the Lambda function with the privileged role
data "archive_file" "privileged_lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/privileged_lambda.zip"
  source {
    content  = <<-EOF
      import json
      def handler(event, context):
          return {
              'statusCode': 200,
              'body': json.dumps('Hello from privileged Lambda!')
          }
    EOF
    filename = "lambda_function.py"
  }
}

resource "aws_lambda_function" "iamws-privileged-lambda" {
  filename         = data.archive_file.privileged_lambda_zip.output_path
  function_name    = "iamws-privileged-lambda"
  role             = aws_iam_role.iamws-privileged-lambda-role.arn
  handler          = "lambda_function.handler"
  runtime          = "python3.11"
  source_code_hash = data.archive_file.privileged_lambda_zip.output_base64sha256
  timeout          = 30
}

# ─────────────────────────────────────────────────────────────────────────────
# THE ATTACKER: A user who can update any Lambda function code
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_iam_policy" "iamws-lambda-developer-policy" {
  name        = "iamws-lambda-developer-policy"
  path        = "/"
  description = "Lambda developer permissions - vulnerable to privesc via UpdateFunctionCode"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowLambdaCodeManagement"
        Effect = "Allow"
        Action = [
          "lambda:UpdateFunctionCode",
          "lambda:GetFunction",
          "lambda:InvokeFunction",
          "lambda:ListFunctions"
        ]
        # ═══════════════════════════════════════════════════════════════════
        # ROOT CAUSE: Can modify ANY Lambda, including privileged ones!
        #
        # THE FIX: Restrict Resource to specific Lambda ARNs:
        # Resource = "arn:aws:lambda:*:*:function:iamws-dev-*"
        #
        # This prevents the attacker from modifying privileged Lambdas.
        # ═══════════════════════════════════════════════════════════════════
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_user" "iamws-lambda-developer-user" {
  name = "iamws-lambda-developer-user"
  path = "/"
}

resource "aws_iam_access_key" "iamws-lambda-developer-user" {
  user = aws_iam_user.iamws-lambda-developer-user.name
}

resource "aws_iam_user_policy_attachment" "iamws-lambda-developer-user-attach" {
  user       = aws_iam_user.iamws-lambda-developer-user.name
  policy_arn = aws_iam_policy.iamws-lambda-developer-policy.arn
}

# Also create a role version for flexibility in the lab
resource "aws_iam_role" "iamws-lambda-developer-role" {
  name = "iamws-lambda-developer-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { AWS = var.aws_assume_role_arn }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "iamws-lambda-developer-role-attach" {
  role       = aws_iam_role.iamws-lambda-developer-role.name
  policy_arn = aws_iam_policy.iamws-lambda-developer-policy.arn
}
