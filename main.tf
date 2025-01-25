locals {
  name   = "ex-karpenter"
  region = var.region

  tags = {
    Example    = local.name
    GithubRepo = "terraform-aws-eks"
    GithubOrg  = "terraform-aws-modules"
  }
}

data "aws_ecrpublic_authorization_token" "token" {
}


################################################################################
# EKS Module
################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.33.0"

  cluster_name    = local.name
  cluster_version = var.cluster_version

  # Gives Terraform identity admin access to cluster which will
  # allow deploying resources (Karpenter) into the cluster
  enable_cluster_creator_admin_permissions = true
  cluster_endpoint_public_access           = true

  cluster_addons = {
    coredns                = {}
    eks-pod-identity-agent = {}
    kube-proxy             = {}
    vpc-cni                = {}
  }


  vpc_id                   = data.terraform_remote_state.vpc.outputs.vpc_id
  subnet_ids               = data.terraform_remote_state.vpc.outputs.private_subnets

  eks_managed_node_groups = {
    karpenter = {
      ami_type       = "BOTTLEROCKET_x86_64"
      instance_types = [var.instance_type]

      min_size     = var.node_group_min_size
      max_size     = var.node_group_max_size
      desired_size = var.node_group_desired_size

      labels = {
        "karpenter.sh/controller" = "true"
      }
    }
  }

  node_security_group_tags = merge(local.tags, {
    # NOTE - if creating multiple security groups with this module, only tag the
    # security group that Karpenter should utilize with the following tag
    # (i.e. - at most, only one security group should have this tag in your account)
    "karpenter.sh/discovery" = local.name
  })

  tags = local.tags
}

################################################################################
# Karpenter
################################################################################

module "karpenter" {
  source = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "20.33.0"

  cluster_name          = module.eks.cluster_name
  enable_v1_permissions = true

  # Name needs to match role name passed to the EC2NodeClass
  node_iam_role_use_name_prefix   = false
  node_iam_role_name              = local.name
  create_pod_identity_association = true

  # Used to attach additional IAM policies to the Karpenter node IAM role
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = local.tags
}

################################################################################
# Karpenter Helm chart & manifests
# Not required; just to demonstrate functionality of the sub-module
################################################################################

resource "helm_release" "karpenter" {
  namespace           = "kube-system"
  name                = "karpenter"
  repository          = "oci://public.ecr.aws/karpenter"
  repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  repository_password = data.aws_ecrpublic_authorization_token.token.password
  chart               = "karpenter"
  version             = "1.1.1"
  wait                = false

  values = [
    <<-EOT
    nodeSelector:
      karpenter.sh/controller: 'true'
    dnsPolicy: Default
    settings:
      clusterName: ${module.eks.cluster_name}
      clusterEndpoint: ${module.eks.cluster_endpoint}
      interruptionQueue: ${module.karpenter.queue_name}
    webhook:
      enabled: false
    EOT
  ]
}

# GPU TIME SLICING

resource "helm_release" "nvidia_device_plugin" {
  name       = "nvdp"
  chart      = "nvidia-device-plugin"
  repository = "https://nvidia.github.io/k8s-device-plugin"
  namespace  = "nvidia-device-plugin"
  create_namespace = true

  version = "0.17.0"

  set {
    name  = "config.name"
    value = "nvidia-device-plugin"
  }


  depends_on = [ module.eks ]
}


# VPC INFORMATION

data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = "challengeterraformstate"  
    key    = "challenge/vpc_statefile"  
    region = local.region
  }
}

