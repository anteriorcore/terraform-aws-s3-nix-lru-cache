# Copyright © 2026 Anterior <tech@anterior.com>
# SPDX-License-Identifier: AGPL-3.0-only

resource "aws_scheduler_schedule" "daily-schedule" {
  name = "trigger-s3-nix-lru-cache-cleanup--${var.cache_bucket_name}"

  schedule_expression = var.lambda_schedule
  flexible_time_window {
    mode                      = "FLEXIBLE"
    maximum_window_in_minutes = 30
  }

  target {
    arn      = aws_lambda_function.cleanup_lambda.arn
    role_arn = aws_iam_role.scheduler_iam_role.arn
  }
}

resource "aws_iam_role" "scheduler_iam_role" {
  name               = "s3-nix-lru-cache-scheduler-role--${var.cache_bucket_name}"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume_role_policy_document.json
}
data "aws_iam_policy_document" "scheduler_assume_role_policy_document" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_policy" "scheduler_trigger_lambda_policy" {
  name   = "s3-nix-lru-cache-scheduler-policy--${var.cache_bucket_name}"
  policy = data.aws_iam_policy_document.scheduler-trigger-lambda-policy-document.json
}
data "aws_iam_policy_document" "scheduler-trigger-lambda-policy-document" {
  statement {
    actions   = ["lambda:InvokeFunction"]
    effect    = "Allow"
    resources = [aws_lambda_function.cleanup_lambda.arn]
  }
}
resource "aws_iam_role_policy_attachment" "scheduler_iam_trigger_attachment" {
  role       = aws_iam_role.scheduler_iam_role.id
  policy_arn = aws_iam_policy.scheduler_trigger_lambda_policy.arn
}
