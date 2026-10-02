data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.module}/src"
  output_path = "${path.module}/handler.zip"
}

resource "aws_kms_key" "events" {
  description         = "KMS key for ${local.name_prefix} serverless data"
  enable_key_rotation = true
  tags                = local.tags
}

resource "aws_dynamodb_table" "events" {
  name         = "${local.name_prefix}-events"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"
  range_key    = "sk"

  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.events.arn
  }

  tags = local.tags
}

resource "aws_sqs_queue" "dlq" {
  name                      = "${local.name_prefix}-lambda-dlq"
  kms_master_key_id         = aws_kms_key.events.arn
  message_retention_seconds = 1209600
  tags                      = local.tags
}

resource "aws_cloudwatch_event_bus" "this" {
  name = local.name_prefix
  tags = local.tags
}

resource "aws_cloudwatch_event_archive" "this" {
  name             = "${local.name_prefix}-archive"
  event_source_arn = aws_cloudwatch_event_bus.this.arn
  retention_days   = 30
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.name_prefix}-api"
  retention_in_days = 90
  kms_key_id        = aws_kms_key.events.arn
  tags              = local.tags
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${local.name_prefix}-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy" "lambda" {
  name = "${local.name_prefix}-lambda"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.lambda.arn}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Query"
        ]
        Resource = aws_dynamodb_table.events.arn
      },
      {
        Effect = "Allow"
        Action = ["events:PutEvents"]
        Resource = aws_cloudwatch_event_bus.this.arn
      },
      {
        Effect = "Allow"
        Action = ["sqs:SendMessage"]
        Resource = aws_sqs_queue.dlq.arn
      },
      {
        Effect = "Allow"
        Action = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = aws_kms_key.events.arn
      }
    ]
  })
}

resource "aws_lambda_function" "api" {
  function_name    = "${local.name_prefix}-api"
  role             = aws_iam_role.lambda.arn
  handler          = "handler.lambda_handler"
  runtime          = var.lambda_runtime
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  memory_size      = var.lambda_memory_mb
  timeout          = var.lambda_timeout_seconds
  kms_key_arn      = aws_kms_key.events.arn

  dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.events.name
      BUS_NAME   = aws_cloudwatch_event_bus.this.name
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda]
  tags       = local.tags
}

resource "aws_lambda_function_event_invoke_config" "api" {
  function_name                = aws_lambda_function.api.function_name
  maximum_event_age_in_seconds = 3600
  maximum_retry_attempts       = 2

  destination_config {
    on_failure {
      destination = aws_sqs_queue.dlq.arn
    }
  }
}

resource "aws_apigatewayv2_api" "this" {
  name          = "${local.name_prefix}-http"
  protocol_type = "HTTP"
  tags          = local.tags
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "proxy" {
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "this" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = var.api_stage_name
  auto_deploy = true
  tags        = local.tags

  default_route_settings {
    throttling_burst_limit = 100
    throttling_rate_limit  = 50
  }
}

resource "aws_lambda_permission" "api" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}
