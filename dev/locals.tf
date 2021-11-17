locals {
  eks_cluster_name = var.eks_cluster_name != "" ? var.eks_cluster_name : var.cluster
  cluster_version = "1.20"
  region = "us-east-1"
}