terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.53.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
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

data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" { state = "available" }

locals {
  aws_eks_charts_repo = "https://aws.github.io/eks-charts"

  aws_lb_controller_helm_name          = "aws-load-balancer-controller"
  aws_lb_controller_helm_chart         = "aws-load-balancer-controller"
  aws_lb_controller_helm_chart_version = "1.8.1"
  aws_lb_controller_service_account    = "aws-load-balancer-controller"
  aws_lb_controller_namespace          = "aws-load-balancer-controller"
  aws_lb_controller_iam_policy_file    = "aws-load-balancer-controller-policy.json"

  prometheus_charts_repo = "https://prometheus-community.github.io/helm-charts"

  kube_prometheus_helm_name          = "prometheus-community"
  kube_prometheus_helm_chart         = "prometheus"
  kube_prometheus_helm_chart_version = "25.22.0"
  kube_prometheus_namespace          = "prometheus"

  grafana_charts_repo = "https://grafana.github.io/helm-charts"

  grafana_helm_name          = "grafana"
  grafana_helm_chart         = "grafana"
  grafana_helm_chart_version = "8.0.2"
  grafana_namespace          = "grafana"

  aws_ebs_csi_driver_namespace = "aws-ebs-csi-driver"
  aws_ebs_csi_driver_service_account = "aws-ebs-csi-driver"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.8.1"

  name                    = "${var.application}-vpc"
  cidr                    = var.vpc_cidr
  azs                     = [data.aws_availability_zones.available.names[0], data.aws_availability_zones.available.names[1]]
  private_subnets         = [cidrsubnet(var.vpc_cidr, 2, 0), cidrsubnet(var.vpc_cidr, 2, 1)]
  public_subnets          = [cidrsubnet(var.vpc_cidr, 2, 2), cidrsubnet(var.vpc_cidr, 2, 3)]
  enable_nat_gateway      = true
  map_public_ip_on_launch = true

  public_subnet_tags = {
    "kubernetes.io/cluster/${var.application}-cluster" = "shared"
    "kubernetes.io/role/elb"                           = 1
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${var.application}-cluster" = "shared"
    "kubernetes.io/role/internal-elb"                  = 1
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name                             = "${var.application}-cluster"
  cluster_version                          = var.kubernetes_version
  cluster_endpoint_public_access           = true
  vpc_id                                   = module.vpc.vpc_id
  subnet_ids                               = module.vpc.private_subnets
  control_plane_subnet_ids                 = module.vpc.intra_subnets
  create_cluster_security_group            = false
  create_node_security_group               = false
  enable_cluster_creator_admin_permissions = true

  cluster_addons = {
    coredns = {
      most_recent = true
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
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = "${aws_iam_role.ebs_csi_driver_service_account_role.arn}"
    }
  }

  fargate_profiles = {
    dev = {
      name = "${var.application}-dev"
      selectors = [
        { namespace = "dev-*" },
      ]
    }

    prod = {
      name = "${var.application}-prod"
      selectors = [
        { namespace = "prod-*" },
      ]
    }

    kube-system = {
      name = "${var.application}-kube-system"
      selectors = [
        { namespace = "kube-system" },
        { namespace = "default" },
      ]
    }

    controllers = {
      name = "${var.application}-controllers"
      selectors = [
        { namespace = "${local.aws_lb_controller_namespace}" },
        { namespace = "${local.kube_prometheus_namespace}" },
        { namespace = "${local.grafana_namespace}" },
      ]
    }
  }
}

resource "aws_iam_policy" "load_balancer_controller_service_account_policy" {
  name   = "${var.application}-lb-policy"
  policy = file("${path.module}/${local.aws_lb_controller_iam_policy_file}")
}

resource "aws_iam_role" "load_balancer_controller_service_account_role" {
  name = "${var.application}-lb-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity",
        Effect = "Allow",
        Principal = {
          Federated = "${module.eks.oidc_provider_arn}",
        },
        Condition = {
          StringEquals = {
            "${module.eks.oidc_provider}:sub" : "system:serviceaccount:${local.aws_lb_controller_namespace}:${local.aws_lb_controller_service_account}",
            "${module.eks.oidc_provider}:aud" : "sts.amazonaws.com",
          }
        },
      },
    ],
  })
}

resource "aws_iam_role_policy_attachment" "load_balancer_controller_policy_attachment" {
  policy_arn = aws_iam_policy.load_balancer_controller_service_account_policy.arn
  role       = aws_iam_role.load_balancer_controller_service_account_role.name
}

resource "aws_iam_role" "ebs_csi_driver_service_account_role" {
  name = "${var.application}-ebs-csi-driver-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity",
        Effect = "Allow",
        Principal = {
          Federated = "${module.eks.oidc_provider_arn}",
        },
        Condition = {
          StringEquals = {
            "${module.eks.oidc_provider}:sub" : "system:serviceaccount:${local.aws_ebs_csi_driver_namespace}:${local.aws_ebs_csi_driver_service_account}",
            "${module.eks.oidc_provider}:aud" : "sts.amazonaws.com",
          }
        },
      },
    ],
  })
}

resource "aws_iam_role_policy_attachment" "ebs_csi_driver_policy_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.ebs_csi_driver_service_account_role.name
}

resource "kubernetes_namespace" "ingress_controller_namespace" {
  metadata {
    name = local.aws_lb_controller_namespace
  }
}

resource "helm_release" "load_balancer_controller_release" {
  name       = local.aws_lb_controller_helm_name
  repository = local.aws_eks_charts_repo
  chart      = local.aws_lb_controller_helm_chart
  namespace  = local.aws_lb_controller_namespace
  version    = local.aws_lb_controller_helm_chart_version

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "awsRegion"
    value = data.aws_region.current.name
  }

  set {
    name  = "rbac.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = local.aws_lb_controller_service_account
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.load_balancer_controller_service_account_role.arn
  }

  set {
    name  = "enableServiceMutatorWebhook"
    value = "false"
  }

  set {
    name  = "vpcId"
    value = module.vpc.vpc_id
  }

  depends_on = [kubernetes_namespace.ingress_controller_namespace]
}

resource "kubernetes_namespace" "kube_prometheus_namespace" {
  metadata {
    name = local.kube_prometheus_namespace
  }
}

resource "helm_release" "kube_prometheus_release" {
  name       = local.kube_prometheus_helm_name
  repository = local.prometheus_charts_repo
  chart      = local.kube_prometheus_helm_chart
  namespace  = local.kube_prometheus_namespace
  version    = local.kube_prometheus_helm_chart_version

  set {
    name  = "prometheus-node-exporter.enabled"
    value = "false"
  }

  set {
    name  = "alertmanager.enabled"
    value = "false"
  }

  set {
    name  = "server.persistentVolume.enabled"
    value = "false"
  }

  depends_on = [kubernetes_namespace.kube_prometheus_namespace]
}

resource "kubernetes_namespace" "grafana_namespace" {
  metadata {
    name = local.grafana_namespace
  }
}

resource "helm_release" "grafana_release" {
  name       = local.grafana_helm_name
  repository = local.grafana_charts_repo
  chart      = local.grafana_helm_chart
  namespace  = local.grafana_namespace
  version    = local.grafana_helm_chart_version

  set {
    name  = "persistence.enabled"
    value = "false"
  }

  set {
    name  = "adminPassword"
    value = "admin"
  }

  set {
    name  = "service.type"
    value = "NodePort"
  }

  depends_on = [kubernetes_namespace.grafana_namespace]
}
