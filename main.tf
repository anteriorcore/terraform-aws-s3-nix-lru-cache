# Copyright © 2026 Anterior <tech@anterior.com>
# SPDX-License-Identifier: AGPL-3.0-only

# Main is mostly glue code.  Creates the bucket to store the
# Python payload and downloads it from GitHub and uploads it
# to s3.
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "random_pet" "slug" {
}
locals {
  slug = random_pet.slug.id
}

data "http" "package_zip" {
  url = var.lambda_zip_source
  request_headers = {
    Accept = "application/octet-stream"
  }
}
resource "aws_s3_bucket" "s3_nix_lru_cache_lambda_assets" {
  # account region namespace.  0-63 name length for buckets.
  bucket = format("nix-lru-assets-%s-%s-%s-an",
    local.slug,
    data.aws_caller_identity.current.account_id,
    data.aws_region.current.region,
  )
  bucket_namespace = "account-regional" # requires aws v6.37
}
resource "aws_s3_bucket_versioning" "lambda_assets_versioning" {
  bucket = aws_s3_bucket.s3_nix_lru_cache_lambda_assets.id
  versioning_configuration {
    status = "Enabled"
  }
}
resource "aws_s3_object" "package_zip_object" {
  bucket         = aws_s3_bucket.s3_nix_lru_cache_lambda_assets.id
  key            = "package.zip"
  content_base64 = data.http.package_zip.response_body_base64
  content_type   = "application/zip"
  source_hash    = base64sha256(data.http.package_zip.response_body_base64)
}
