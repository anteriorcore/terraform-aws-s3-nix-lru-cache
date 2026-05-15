# Copyright © 2026 Anterior <tech@anterior.com>
# SPDX-License-Identifier: AGPL-3.0-only

resource "aws_iam_role" "lambda_iam_role" {
  name               = "s3-nix-lru-cache-lambda-role-${local.slug}"
  assume_role_policy = data.aws_iam_policy_document.assume_role_lambda_policy.json
}
data "aws_iam_policy_document" "assume_role_lambda_policy" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role_policy_attachment" "vpc_lambda_policy_attachment" {
  role = aws_iam_role.lambda_iam_role.id
  # this is an AWS managed role which allows logs and network interface creation
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_policy" "bucket_access_lambda_policy" {
  policy = data.aws_iam_policy_document.bucket_access_lambda_policy.json
  name   = "s3-nix-lru-cache-bucket_access_lambda_policy-${local.slug}"
}
data "aws_iam_policy_document" "bucket_access_lambda_policy" {
  statement {
    effect  = "Allow"
    actions = ["s3:GetObject", "s3:ListBucket", "s3:DeleteObject"]
    resources = [
      aws_s3_bucket.cache_bucket.arn,
      aws_s3_bucket.logs_bucket.arn,
      "${aws_s3_bucket.cache_bucket.arn}/*",
      "${aws_s3_bucket.logs_bucket.arn}/*"
    ]
  }
}
resource "aws_iam_role_policy_attachment" "bucket_access_lambda_policy_attachment" {
  role       = aws_iam_role.lambda_iam_role.id
  policy_arn = aws_iam_policy.bucket_access_lambda_policy.arn
}

locals {
  lambda_fn_name = "s3-nix-lru-cache-${local.slug}"
}
resource "aws_lambda_function" "cleanup_lambda" {
  role             = aws_iam_role.lambda_iam_role.arn
  function_name    = local.lambda_fn_name
  runtime          = "python3.14"
  timeout          = 60 * 5
  memory_size      = 512
  handler          = "main.aws_lambda"
  architectures    = ["x86_64"]
  package_type     = "Zip"
  s3_bucket        = aws_s3_object.package_zip_object.bucket
  s3_key           = aws_s3_object.package_zip_object.key
  source_code_hash = base64sha256(data.http.package_zip.response_body_base64)
  depends_on       = [aws_iam_role.lambda_iam_role]

  environment {
    variables = tomap({
      CACHE_LOGS_NAME = aws_s3_bucket.logs_bucket.id
      CACHE_NAME      = aws_s3_bucket.cache_bucket.id
      LOG_LEVEL       = var.lambda_log_level
      # the access logs are saved with the following prefix for the cache
      LOGS_KEY_PREFIX = "${data.aws_caller_identity.current.account_id}/${data.aws_region.current.region}/${aws_s3_bucket.cache_bucket.id}/"
      # A bit hokey, but the actual "assumed role" that shows up in the access logs is this thing.
      ROLE = "arn:aws:sts::${data.aws_caller_identity.current.account_id}:assumed-role/${aws_iam_role.lambda_iam_role.name}/${local.lambda_fn_name}"
    })
  }

  dynamic "vpc_config" {
    # tf idiom to set a block conditionally
    for_each = var.lambda_vpc != null ? toset([1]) : toset([])
    content {
      # Apparently there's no way to directly take this variable object or
      # splat it here.  Allegedly that's a feature not a bug to decouple
      # variables from provider definitions...
      subnet_ids                  = var.lambda_vpc.subnet_ids
      security_group_ids          = var.lambda_vpc.security_group_ids
      ipv6_allowed_for_dual_stack = var.lambda_vpc.ipv6_allowed_for_dual_stack
    }
  }

}
