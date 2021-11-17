data "aws_availability_zones" "available" {}

provider "aws" {
  region = local.region
}

resource "random_string" "random" {
  length = 16
  special = false
}

################################################################################
# VPC Module
################################################################################


module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.11.0"

  name                 = "${var.environment}-${var.name}"
  cidr                 = var.cidr
  azs                  = data.aws_availability_zones.available.names
  private_subnets      = var.private_subnets
  public_subnets       = var.public_subnets
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  tags = {
    "kubernetes.io/cluster/${var.name}" = "shared",
  }

  public_subnet_tags = {
    "kubernetes.io/cluster/${var.name}" = "shared"
    "kubernetes.io/role/elb"                          = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${var.name}" = "shared"
    "kubernetes.io/role/internal-elb"                 = "1"
  }
}

################################################################################
# EKS Module
################################################################################

module "eks" {
  source = "terraform-aws-modules/eks/aws"

  cluster_name    = "${var.name}-${random_string.random.result}"
  cluster_version = local.cluster_version

  vpc_id          = module.vpc.vpc_id
  subnets         = [module.vpc.private_subnets[0], module.vpc.public_subnets[1]]
  fargate_subnets = [module.vpc.private_subnets[2]]

  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true

  # You require a node group to schedule coredns which is critical for running correctly internal DNS.
  # If you want to use only fargate you must follow docs `(Optional) Update CoreDNS`
  # available under https://docs.aws.amazon.com/eks/latest/userguide/fargate-getting-started.html
  node_groups = {
    example = {
      desired_capacity = 3

      instance_types = ["t3.micro"]
      k8s_labels = {
        Example    = "managed_node_groups"
        GithubRepo = "terraform-aws-eks"
        GithubOrg  = "terraform-aws-modules"
      }
      additional_tags = {
        ExtraTag = "example"
      }
      update_config = {
        max_unavailable_percentage = 50 # or set `max_unavailable`
      }
    }
  }

  fargate_profiles = {
    default = {
      name = "default"
      selectors = [
        {
          namespace = "kube-system"
          labels = {
            k8s-app = "kube-dns"
          }
        },
        {
          namespace = "default"
          labels = {
            WorkerType = "fargate"
          }
        }
      ]

      tags = {
        Owner = "default"
      }

      timeouts = {
        create = "20m"
        delete = "20m"
      }
    }

    secondary = {
      name = "secondary"
      selectors = [
        {
          namespace = "default"
          labels = {
            Environment = "test"
            GithubRepo  = "terraform-aws-eks"
            GithubOrg   = "terraform-aws-modules"
          }
        }
      ]

      # Using specific subnets instead of the ones configured in EKS (`subnets` and `fargate_subnets`)
      subnets = [module.vpc.private_subnets[1]]

      tags = {
        Owner = "secondary"
      }
    }
  }

  manage_aws_auth = false

  tags = {
    Example    = var.name
    GithubRepo = "terraform-aws-eks"
    GithubOrg  = "terraform-aws-modules"
  }
}

################################################################################
# Argo CD
################################################################################

module "argo_cd" {
  source = "runoncloud/argocd/kubernetes"

  namespace       = "argocd"
  argo_cd_version = "1.8.7"
}