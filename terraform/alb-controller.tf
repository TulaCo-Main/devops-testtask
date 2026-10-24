################################################################################
# AWS Load Balancer Controller
#
# IRSA permissions for the controller installed by install.sh.
################################################################################

# Policy source: kubernetes-sigs/aws-load-balancer-controller v3.6.1, docs/install/iam_policy.json.
locals {
  alb_controller_service_account = "aws-load-balancer-controller"
}

resource "aws_iam_policy" "alb_controller" {
  name        = "${var.cluster_name}-alb-controller"
  description = "Permissions for the AWS Load Balancer Controller"
  policy      = file("${path.module}/alb-controller-iam-policy.json")
}

module "alb_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.44.0"

  role_name = "${var.cluster_name}-alb-controller"

  role_policy_arns = {
    policy = aws_iam_policy.alb_controller.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:${local.alb_controller_service_account}"]
    }
  }
}
