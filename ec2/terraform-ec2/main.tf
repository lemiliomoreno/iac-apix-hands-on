terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.53.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

resource "aws_instance" "apix_example" {
  ami           = "ami-0cf2b4e024cdb6960"
  instance_type = "t3.micro"

  tags = {
    Name = "ApixExample"
  }
}
