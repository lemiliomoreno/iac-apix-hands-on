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

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "apix-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-west-2a", "us-west-2b", ]
  private_subnets = ["10.0.0.0/18", "10.0.64.0/18"]
  public_subnets  = ["10.0.128.0/18", "10.0.192.0/18"]

  enable_nat_gateway      = true
  map_public_ip_on_launch = true
}

resource "aws_security_group" "database_sg" {
  name   = "apix-db-sg"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port        = 5432
    to_port          = 5432
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_db_subnet_group" "database_subnets" {
  name       = "apix-db-subnet-group"
  subnet_ids = module.vpc.public_subnets
}

resource "aws_rds_cluster" "database_cluster" {
  cluster_identifier = "apix-database-cluster"
  engine             = "aurora-postgresql"
  engine_version     = "16.1"
  database_name      = "postgres"
  master_username    = "postgres"
  engine_mode        = "provisioned"
  master_password    = "mysupersecretpassword"
  backup_retention_period = 1
  skip_final_snapshot     = true

  vpc_security_group_ids = [
    aws_security_group.database_sg.id,
  ]

  db_subnet_group_name = aws_db_subnet_group.database_subnets.id

  serverlessv2_scaling_configuration {
    min_capacity = 0.5
    max_capacity = 16.0
  }
}

resource "aws_rds_cluster_instance" "database_instance_writer_1" {
  cluster_identifier   = aws_rds_cluster.database_cluster.id
  instance_class       = "db.serverless"
  engine               = aws_rds_cluster.database_cluster.engine
  engine_version       = aws_rds_cluster.database_cluster.engine_version
  db_subnet_group_name = aws_db_subnet_group.database_subnets.id
  publicly_accessible  = true
}
