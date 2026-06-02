# Copyright © 2026 Anterior <tech@anterior.com>
# SPDX-License-Identifier: AGPL-3.0-only

resource "aws_s3_bucket" "cache_bucket" {
  # account region namespace
  bucket = format("%s--%s-%s-an",
    var.cache_bucket_name,
    data.aws_caller_identity.current.account_id,
    data.aws_region.current.region,
  )
  bucket_namespace = "account-regional" # requires aws v6.37
}
resource "aws_s3_bucket_versioning" "cache_bucket_versioning" {
  bucket = aws_s3_bucket.cache_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket" "logs_bucket" {
  bucket = format("%s--logs-%s-%s-an",
    var.cache_bucket_name,
    data.aws_caller_identity.current.account_id,
    data.aws_region.current.region,
  )
  bucket_namespace = "account-regional"
}
resource "aws_s3_bucket_lifecycle_configuration" "log_bucket_lifecycle" {
  bucket = aws_s3_bucket.logs_bucket.id
  rule {
    filter {
      # By default ignores objects smaller than 128KB but since these are small
      # access logs that point to the caches files, we don't want to save small
      # files here.
      object_size_greater_than = 1
    }
    id     = "delete-logs-after-${var.retention_days}-days"
    status = "Enabled"
    expiration {
      days = var.retention_days
    }
  }
}
resource "aws_s3_bucket_policy" "logs_bucket_policy" {
  bucket = aws_s3_bucket.logs_bucket.id
  policy = data.aws_iam_policy_document.log_bucket_policy_data.json
}
data "aws_iam_policy_document" "log_bucket_policy_data" {
  statement {
    sid    = "S3ServerAccessLogsPolicy"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.logs_bucket.arn}/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_s3_bucket_logging" "cache_access_logs" {
  bucket        = aws_s3_bucket.cache_bucket.id
  target_bucket = aws_s3_bucket.logs_bucket.id
  target_prefix = ""
  target_object_key_format {
    partitioned_prefix {
      partition_date_source = "EventTime"
    }
  }
}

# encryption for both buckets
resource "aws_s3_bucket_server_side_encryption_configuration" "bucket_encryption" {
  for_each = tomap({
    cache = aws_s3_bucket.cache_bucket.id
    logs  = aws_s3_bucket.logs_bucket.id
  })
  bucket = each.value
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled       = true
    blocked_encryption_types = ["SSE-C"]
  }
}
