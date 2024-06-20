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

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
      command     = "aws"
    }
  }
}

data "aws_region" "current" {}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "5.8.1"

  name = "apix-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-west-2a", "us-west-2b", ]
  private_subnets = ["10.0.0.0/18", "10.0.64.0/18"]
  public_subnets  = ["10.0.128.0/18", "10.0.192.0/18"]

  enable_nat_gateway      = true
  map_public_ip_on_launch = true
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "apix-eks-cluster"
  cluster_version = "1.30"

  cluster_endpoint_public_access = true

  cluster_addons = {
    coredns = {
      configuration_values = jsonencode({
        computeType = "fargate"
      })
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
  }

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.intra_subnets

  create_cluster_security_group = false
  create_node_security_group    = false

  enable_cluster_creator_admin_permissions = true

  fargate_profiles = {

    dev = {
      name = "dev"
      selectors = [
        { namespace = "dev-*" },
      ]
    }

    kube-system = {
      selectors = [
        { namespace = "kube-system" },
        { namespace = "default" },
      ]
    }

    controllers = {
      selectors = [
        { namespace = "aws-*" },
      ]
    }
  }
}

module "lb_role" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.39.1"

  role_name                              = "apix-eks-lb-role"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

resource "kubernetes_namespace" "ingress_controller_namespace" {
  metadata {
    name = "aws-load-balancer-controller-crds"
  }
}

# resource "helm_release" "ingress_release" {
#   name       = "ingress-aws"
#   repository = "https://aws.github.io/eks-charts"
#   chart      = "aws-load-balancer-controller"
#   namespace  = "aws-load-balancer-controller-crds"
#   version    = "1.8.1"

#   set {
#     name  = "clusterName"
#     value = module.eks.cluster_name
#   }

#   set {
#     name  = "awsRegion"
#     value = data.aws_region.current.name
#   }

#   set {
#     name  = "rbac.create"
#     value = "true"
#   }

#   set {
#     name  = "serviceAccount.name"
#     value = "aws-load-balancer-controller"
#   }

#   set {
#     name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
#     value = module.lb_role.iam_role_arn
#   }

#   set {
#     name  = "enableServiceMutatorWebhook"
#     value = "false"
#   }

#   depends_on = [kubernetes_namespace.ingress_controller_namespace]
# }
