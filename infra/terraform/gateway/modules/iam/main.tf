data "aws_caller_identity" "current" {}

resource "aws_iam_role" "gateway" {
  name = "${var.gateway_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "bedrock.amazonaws.com"
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = var.account_id
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "gateway_cloudwatch" {
  role       = aws_iam_role.gateway.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

resource "aws_iam_role_policy" "gateway_secrets" {
  count = var.use_api_key ? 1 : 0
  name  = "SecretsManagerAccess"
  role  = aws_iam_role.gateway.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = var.api_key_secret_arn
    }]
  })
}
