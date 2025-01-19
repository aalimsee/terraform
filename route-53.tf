#==========================================================
# Reference to existing Route 53 Hosted Zone
#==========================================================
data "aws_route53_zone" "existing_zone" {
  name = "sctp-sandbox.com" # Replace with your exact domain
}

#==========================================================
# Route 53 Record for Web Load Balancer
#==========================================================
resource "aws_route53_record" "public_alb" { # <<< why "public_alb"
  zone_id = data.aws_route53_zone.existing_zone.id
  name    = "aalimsee-tf-web" # Subdomain for the web service
  type    = "A"
  alias {
    name                   = aws_lb.public_alb.dns_name
    zone_id                = aws_lb.public_alb.zone_id
    evaluate_target_health = true
  }
}

#==========================================================
# Request a new ACM Certificate for your domain
#==========================================================
resource "aws_acm_certificate" "https_cert" {
  domain_name       = "aalimsee-tf-web.sctp-sandbox.com" # Replace with your domain
  # <<< change to sctp-sandbox.com
  validation_method = "DNS"

  tags = {
    Name = "${var.prefix}-HTTPS-Certificate"
    CreatedBy = "${var.createdByTerraform}"
  }

  lifecycle {
    create_before_destroy = true
  }
}

#==========================================================
# Create DNS validation records in the existing Route 53 Hosted Zone
#==========================================================
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.https_cert.domain_validation_options :
    dvo.domain_name => {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  }

  zone_id = data.aws_route53_zone.existing_zone.id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.value]
  ttl     = 300
}

#==========================================================
# Validate the ACM Certificate
#==========================================================
resource "aws_acm_certificate_validation" "https_cert_validation" {
  certificate_arn         = aws_acm_certificate.https_cert.arn

  validation_record_fqdns = [
    for record in aws_route53_record.cert_validation : record.fqdn
  ]
}



# <<< add this block
# Attach the new certificate to the existing HTTPS listener
#resource "aws_lb_listener_certificate" "https_cert_attach" {
  #listener_arn    = data.aws_lb_listener.existing_listener.arn
#  listener_arn    = data.aws_lb_listener.public_listener.arn
#  certificate_arn = aws_acm_certificate_validation.https_cert_validation.certificate_arn
#}

# Configure an HTTPS Listener for the existing ALB
#resource "aws_lb_listener" "https_listener" {
#  load_balancer_arn = data.aws_lb.existing_alb.arn
#  port              = 443
#  protocol          = "HTTPS"

#  ssl_policy        = "ELBSecurityPolicy-2016-08"
#  certificate_arn   = aws_acm_certificate_validation.https_cert_validation.certificate_arn

#  default_action {
#    type = "forward"
    #target_group_arn = data.aws_lb_target_group.existing_target_group.arn
#    target_group_arn = data.aws_autoscaling_group.web_asg.public_tg.arn
#  }
#}