terraform {
    required_providers {
      aws = {
        source = "hashicorp/aws"
        version = "~> 5.53.0"
      }
    }
}

provider "aws" {
  region = "us-west-2"
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "apix-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-west-2a", "us-west-2b",]
  private_subnets = ["10.0.0.0/18", "10.0.64.0/18"]
  public_subnets  = ["10.0.128.0/18", "10.0.192.0/18"]

  enable_nat_gateway = true
}
