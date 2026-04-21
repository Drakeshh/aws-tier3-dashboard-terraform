terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket = "terraform-state-static-website-sergiprat"
    key    = "3tier-dashboard/terraform.tfstate"
    region = "eu-west-3"
  }
}

provider "aws" {
  region = var.aws_region
}

# us-east-1 provider needed for ACM certificate (CloudFront requirement)
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}