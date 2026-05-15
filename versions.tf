# Copyright © 2026 Anterior <tech@anterior.com>
# SPDX-License-Identifier: AGPL-3.0-only

terraform {
  required_version = ">= 1.12.2"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~>6.37" # v6.37 for account regional namespace
    }
    http = {
      source  = "hashicorp/http"
      version = "~>3.5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~>3.8.0"
    }
  }
}
