module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.29.0"

  name               = var.cluster_name
  kubernetes_version = var.cluster_version

  endpoint_public_access       = true
  endpoint_private_access      = true
  endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  enable_irsa = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # The module attaches AmazonEKSFargatePodExecutionRolePolicy for ECR pulls.
  fargate_profiles = {
    # CoreDNS must run on Fargate too — there are no EC2 nodes in this cluster.
    kube_system = {
      name = "kube-system"
      selectors = [
        {
          namespace = "kube-system"
          labels = {
            "k8s-app" = "kube-dns"
          }
        },
        {
          namespace = "kube-system"
          labels = {
            "app.kubernetes.io/name" = "aws-load-balancer-controller"
          }
        }
      ]
      subnet_ids = module.vpc.private_subnets
    }

    # Each application Deployment selects a profile with exactly one AZ.
    apps_a = {
      name = "apps-a"
      selectors = [
        {
          namespace = var.app_namespace
        }
      ]
      subnet_ids = [module.vpc.private_subnets[0]]
    }

    apps_b = {
      name = "apps-b"
      selectors = [
        {
          namespace = var.app_namespace
        }
      ]
      subnet_ids = [module.vpc.private_subnets[1]]
    }
  }

  # Cluster add-ons. CoreDNS is patched to run on Fargate via the compute config.
  addons = {
    coredns = {
      addon_version = var.coredns_version
      configuration_values = jsonencode({
        computeType = "Fargate"
        resources = {
          limits   = { cpu = "0.25", memory = "256M" }
          requests = { cpu = "0.25", memory = "256M" }
        }
      })
    }
  }

  # Give the operator running `terraform apply` cluster-admin so kubeconfig works
  # immediately. In real production you would use access entries with least
  # privilege and SSO.
  enable_cluster_creator_admin_permissions = true

  tags = {
    Project = var.project
  }
}
