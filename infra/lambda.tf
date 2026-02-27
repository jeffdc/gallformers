# Lambda health check + CloudWatch scheduling + SNS alerting.
#
# Pings https://www.gallformers.org every 5 minutes. On failure the Lambda
# throws, CloudWatch detects the error metric, and the alarm publishes to
# an SNS topic that fans out to email.

# -----------------------------------------------------------------------------
# SNS Topic + Subscriptions
# -----------------------------------------------------------------------------

resource "aws_sns_topic" "downdetector" {
  name = "gallformers-downdetector"

  tags = {
    Project   = var.project
    ManagedBy = "opentofu"
  }
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.downdetector.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# -----------------------------------------------------------------------------
# Lambda Function
# -----------------------------------------------------------------------------

data "archive_file" "downdetector" {
  type        = "zip"
  source_file = "${path.module}/lambda/downdetector.mjs"
  output_path = "${path.module}/lambda/downdetector.zip"
}

resource "aws_lambda_function" "downdetector" {
  function_name    = "gallformers-downdetector"
  role             = aws_iam_role.lambda_downdetector.arn
  handler          = "downdetector.handler"
  runtime          = "nodejs20.x"
  timeout          = 10
  memory_size      = 128
  filename         = data.archive_file.downdetector.output_path
  source_code_hash = data.archive_file.downdetector.output_base64sha256

  environment {
    variables = {
      SITE_URL = "https://www.gallformers.org"
    }
  }

  tags = {
    Project   = var.project
    ManagedBy = "opentofu"
  }
}

# -----------------------------------------------------------------------------
# IAM Role for Lambda
# -----------------------------------------------------------------------------

resource "aws_iam_role" "lambda_downdetector" {
  name = "gallformers-downdetector-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  inline_policy {
    name = "downdetector-permissions"

    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Sid    = "SNSPublish"
          Effect = "Allow"
          Action = "sns:Publish"
          Resource = aws_sns_topic.downdetector.arn
        },
        {
          Sid    = "CloudWatchLogs"
          Effect = "Allow"
          Action = [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents",
          ]
          Resource = "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:*"
        }
      ]
    })
  }

  tags = {
    Project   = var.project
    ManagedBy = "opentofu"
  }
}

# -----------------------------------------------------------------------------
# CloudWatch Event Rule (Schedule)
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "downdetector" {
  name                = "gallformers-downdetector"
  description         = "Trigger health check every 5 minutes"
  schedule_expression = "rate(5 minutes)"

  tags = {
    Project   = var.project
    ManagedBy = "opentofu"
  }
}

resource "aws_cloudwatch_event_target" "downdetector" {
  rule = aws_cloudwatch_event_rule.downdetector.name
  arn  = aws_lambda_function.downdetector.arn
}

resource "aws_lambda_permission" "downdetector" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.downdetector.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.downdetector.arn
}

# -----------------------------------------------------------------------------
# CloudWatch Alarm (triggers SNS on Lambda errors)
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "downdetector" {
  alarm_name          = "gallformers-downdetector-errors"
  alarm_description   = "Gallformers health check failures"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.downdetector.function_name
  }

  alarm_actions = [aws_sns_topic.downdetector.arn]
  ok_actions    = [aws_sns_topic.downdetector.arn]

  tags = {
    Project   = var.project
    ManagedBy = "opentofu"
  }
}
