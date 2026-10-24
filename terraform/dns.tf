data "aws_route53_zone" "main" {
  zone_id = "Z03826222YIG8RVFQGG21"
}

# The first apply has no ALB; apply again after install.sh to create the alias.
data "aws_lbs" "nodeapp" {
  tags = {
    "elbv2.k8s.aws/cluster"     = var.cluster_name
    "gateway.k8s.aws.alb/stack" = "${var.app_namespace}/nodeapp"
  }
}

data "aws_lb" "nodeapp" {
  count = length(data.aws_lbs.nodeapp.arns) > 0 ? 1 : 0
  arn   = one(data.aws_lbs.nodeapp.arns)
}

resource "aws_route53_record" "nodeapp" {
  count   = length(data.aws_lb.nodeapp)
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "nodeapp.tulaco.click"
  type    = "A"

  alias {
    name                   = data.aws_lb.nodeapp[0].dns_name
    zone_id                = data.aws_lb.nodeapp[0].zone_id
    evaluate_target_health = true
  }
}
