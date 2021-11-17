terraform {
  required_version = "~> 0.12.0"

  required_providers {
    source = "hashicorp/aws"
    aws = "~> 3.65.0"
    local = ">= 1.4"
    random = ">= 2.1"
    kubernetes = "~> 2.0"
  }
}