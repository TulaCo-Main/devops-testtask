resource "aws_acm_certificate" "wildcard" {
  domain_name       = "*.tulaco.click"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "certificate_validation" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = one(aws_acm_certificate.wildcard.domain_validation_options).resource_record_name
  type    = one(aws_acm_certificate.wildcard.domain_validation_options).resource_record_type
  records = [one(aws_acm_certificate.wildcard.domain_validation_options).resource_record_value]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "wildcard" {
  certificate_arn         = aws_acm_certificate.wildcard.arn
  validation_record_fqdns = [aws_route53_record.certificate_validation.fqdn]
}
