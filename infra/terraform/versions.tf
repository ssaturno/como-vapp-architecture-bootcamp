terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    bucket  = "como-vapp-terraform-state-886240425170"
    key     = "como-vapp/dev/terraform.tfstate"
    region  = "us-east-1"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}
