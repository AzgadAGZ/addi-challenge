terraform {
  required_version = ">= 1.11.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.51"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.2"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.2"
    }
  }
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

locals {
  common_tags = merge(
    {
      Environment = var.environment
      ManagedBy   = "addi-platform"
      Project     = "addi"
    },
    var.tags,
  )
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.23"

  name               = var.cluster_name
  kubernetes_version = var.cluster_version

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  endpoint_private_access      = true
  endpoint_public_access       = length(var.allowed_cidrs) > 0 ? true : false
  endpoint_public_access_cidrs = length(var.allowed_cidrs) > 0 ? var.allowed_cidrs : null

  enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  encryption_config = {
    provider_key_arn = var.kms_key_arn != "" ? var.kms_key_arn : null
    resources        = ["secrets"]
  }

  # Pod Identity agent addon
  enable_cluster_creator_admin_permissions = true

  addons = {
    eks-pod-identity-agent = {
      most_recent = true
    }
    coredns = {
      most_recent                 = true
      resolve_conflicts_on_update = "OVERWRITE"
    }
  }

  eks_managed_node_groups = {
    general = {
      instance_types = var.node_instance_types
      capacity_type  = "SPOT"

      min_size     = 1
      max_size     = 10
      desired_size = 2

      labels = {
        role        = "general"
        environment = var.environment
      }

      tags = local.common_tags
    }

    critical = {
      instance_types = var.critical_instance_types
      capacity_type  = "ON_DEMAND"

      min_size     = 1
      max_size     = 6
      desired_size = 2

      labels = {
        role        = "critical"
        environment = var.environment
      }

      taints = {
        dedicated = {
          key    = "dedicated"
          value  = "critical"
          effect = "NO_SCHEDULE"
        }
      }

      tags = local.common_tags
    }
  }

  tags = local.common_tags
}

# Karpenter NodePool - general workloads (spot + on-demand)
resource "kubernetes_manifest" "karpenter_nodepool_general" {
  manifest = {
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = "general-nodepool"
    }
    spec = {
      template = {
        metadata = {
          labels = {
            role        = "general"
            environment = var.environment
          }
        }
        spec = {
          requirements = [
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = ["spot", "on-demand"]
            },
            {
              key      = "node.kubernetes.io/instance-type"
              operator = "In"
              values   = var.node_instance_types
            },
            {
              key      = "karpenter.k8s.aws/instance-family"
              operator = "In"
              values   = ["m5", "m6i", "c5", "c6i"]
            },
          ]
          nodeClassRef = {
            apiVersion = "karpenter.k8s.aws/v1"
            kind       = "EC2NodeClass"
            name       = "default"
          }
        }
      }
      limits = {
        cpu    = "1000"
        memory = "1000Gi"
      }
      disruption = {
        consolidationPolicy = "WhenEmptyOrUnderutilized"
        consolidateAfter    = "30s"
        expireAfter         = "720h"
      }
    }
  }

  depends_on = [module.eks, helm_release.karpenter]
}

# Karpenter NodePool - critical workloads (on-demand only)
resource "kubernetes_manifest" "karpenter_nodepool_critical" {
  manifest = {
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = "critical-nodepool"
    }
    spec = {
      template = {
        metadata = {
          labels = {
            role        = "critical"
            environment = var.environment
          }
        }
        spec = {
          requirements = [
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = ["on-demand"]
            },
            {
              key      = "node.kubernetes.io/instance-type"
              operator = "In"
              values   = var.critical_instance_types
            },
            {
              key      = "karpenter.k8s.aws/instance-family"
              operator = "In"
              values   = ["m5", "m6i"]
            },
          ]
          taints = [
            {
              key    = "dedicated"
              value  = "critical"
              effect = "NoSchedule"
            }
          ]
          nodeClassRef = {
            apiVersion = "karpenter.k8s.aws/v1"
            kind       = "EC2NodeClass"
            name       = "default"
          }
        }
      }
      limits = {
        cpu    = "200"
        memory = "400Gi"
      }
      disruption = {
        consolidationPolicy = "WhenEmpty"
        consolidateAfter    = "30s"
        expireAfter         = "720h"
      }
    }
  }

  depends_on = [module.eks, helm_release.karpenter]
}

# Cilium CNI - replaces kube-proxy and vpc-cni, adds eBPF networking,
# Hubble observability, WireGuard encryption, and L7 policy enforcement.
resource "helm_release" "cilium" {
  name       = "cilium"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  version    = "1.17.1"
  namespace  = "kube-system"

  set = [
    { name = "kubeProxyReplacement", value = "true" },
    { name = "hubble.enabled", value = "true" },
    { name = "hubble.relay.enabled", value = "true" },
    { name = "hubble.ui.enabled", value = "true" },
    { name = "serviceMesh.enabled", value = "true" },
    { name = "encryption.enabled", value = "true" },
    { name = "encryption.type", value = "wireguard" },
    { name = "networkPolicy.enabled", value = "true" },
  ]

  depends_on = [module.eks]
}

# Karpenter controller - auto-provisioning for scale events
resource "helm_release" "karpenter" {
  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = "1.3.0"
  namespace  = "kube-system"

  set = [
    { name = "settings.clusterName", value = module.eks.cluster_name },
    { name = "settings.interruptionQueue", value = module.eks.cluster_name },
    { name = "controller.resources.requests.cpu", value = "1" },
    { name = "controller.resources.requests.memory", value = "1Gi" },
  ]

  depends_on = [module.eks]
}
