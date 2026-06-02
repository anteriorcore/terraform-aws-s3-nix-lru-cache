# Copyright © 2026 Anterior <tech@anterior.com>
# SPDX-License-Identifier: AGPL-3.0-only

variable "cache_bucket_name" {
  type        = string
  description = "Name of the cache bucket.  It is appended with your account ID etc to make it a regional namespace.  Is also used to name the aceess log bucket."
  default     = "nix-lru-cache"
}

variable "retention_days" {
  type        = number
  description = "How many days to retain access logs. Will therefore keep cache items used within that number of days."
  default     = 30
  nullable    = false
  validation {
    condition     = var.retention_days > 0
    error_message = "retention_days must be greater than 0"
  }
}

variable "lambda_schedule" {
  type = string
  # 5am UTC is 12am EST and 1am EDT (NY), 5am GMT and 6am
  # BST (London).
  default     = "cron(0 5 * * ? *)"
  description = "When to run the lambda function.  This is NOT the same as your cache retention.  Should probably be about every day or more frequent."
}

variable "lambda_log_level" {
  type        = string
  description = "Set the Python Lambda log level. Must be one of CRITICAL, ERROR, WARNING, INFO, DEBUG"
  default     = "DEBUG"
  validation {
    condition     = contains(["CRITICAL", "ERROR", "WARNING", "INFO", "DEBUG"], var.lambda_log_level)
    error_message = "Must be one of CRITICAL, ERROR, WARNING, INFO, DEBUG."
  }
}

# optional vpc config
variable "lambda_vpc" {
  type = object({
    subnet_ids                  = list(string)
    security_group_ids          = list(string)
    ipv6_allowed_for_dual_stack = optional(bool, "false")
  })
  nullable = true
  default  = null
}

variable "lambda_zip_source" {
  type        = string
  default     = "https://github.com/anteriorcore/terraform-aws-s3-nix-lru-cache/releases/download/latest-X64-Linux/package.zip"
  description = "Where to download the zip bundle to upload to s3 and use as the lambda source for cleaning the cache.  The default is the latest build artifact from this repo."
}
