# Copyright © 2026 Anterior <tech@anterior.com>
# SPDX-License-Identifier: AGPL-3.0-only

output "cache_bucket_name" {
  value = aws_s3_bucket.cache_bucket.id
}
output "logs_bucket_name" {
  value = aws_s3_bucket.logs_bucket.id
}

output "cache_bucket_arn" {
  value = aws_s3_bucket.cache_bucket.arn
}
output "logs_bucket_arn" {
  value = aws_s3_bucket.logs_bucket.arn
}
