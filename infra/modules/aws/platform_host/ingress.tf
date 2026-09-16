resource "aws_acm_certificate" "platform" {
  domain_name               = local.backstage_hostname
  subject_alternative_names = [local.argocd_hostname]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "certificate_validation" {
  for_each = {
    for option in aws_acm_certificate.platform.domain_validation_options :
    option.domain_name => {
      name   = option.resource_record_name
      record = option.resource_record_value
      type   = option.resource_record_type
    }
  }

  allow_overwrite = true
  zone_id         = data.aws_route53_zone.public.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
}

resource "aws_acm_certificate_validation" "platform" {
  certificate_arn = aws_acm_certificate.platform.arn
  validation_record_fqdns = [
    for record in aws_route53_record.certificate_validation : record.fqdn
  ]
}

resource "aws_lb" "platform" {
  name               = substr("${var.base_name}-platform", 0, 32)
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.load_balancer_security_group_id]
  subnets            = sort(data.aws_subnets.public.ids)
}

resource "aws_lb_target_group" "backstage" {
  name                 = substr("${var.base_name}-backstage", 0, 32)
  port                 = 30070
  protocol             = "HTTP"
  target_type          = "instance"
  vpc_id               = data.aws_vpc.this.id
  deregistration_delay = 10

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 15
    matcher             = "200"
    path                = "/.backstage/health/v1/readiness"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 4
  }
}

resource "aws_lb_target_group" "argocd" {
  name                 = substr("${var.base_name}-argocd", 0, 32)
  port                 = 30443
  protocol             = "HTTPS"
  target_type          = "instance"
  vpc_id               = data.aws_vpc.this.id
  deregistration_delay = 10

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 15
    matcher             = "200"
    path                = "/healthz"
    port                = "traffic-port"
    protocol            = "HTTPS"
    timeout             = 5
    unhealthy_threshold = 4
  }
}

resource "aws_lb_target_group_attachment" "backstage" {
  target_group_arn = aws_lb_target_group.backstage.arn
  target_id        = aws_instance.this.id
  port             = 30070
}

resource "aws_lb_target_group_attachment" "argocd" {
  target_group_arn = aws_lb_target_group.argocd.arn
  target_id        = aws_instance.this.id
  port             = 30443
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.platform.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.platform.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = aws_acm_certificate_validation.platform.certificate_arn
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Not found"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener_rule" "backstage" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backstage.arn
  }

  condition {
    host_header {
      values = [local.backstage_hostname]
    }
  }
}

resource "aws_lb_listener_rule" "argocd" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.argocd.arn
  }

  condition {
    host_header {
      values = [local.argocd_hostname]
    }
  }
}

resource "aws_route53_record" "backstage" {
  zone_id = data.aws_route53_zone.public.zone_id
  name    = local.backstage_hostname
  type    = "A"

  alias {
    name                   = aws_lb.platform.dns_name
    zone_id                = aws_lb.platform.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "argocd" {
  zone_id = data.aws_route53_zone.public.zone_id
  name    = local.argocd_hostname
  type    = "A"

  alias {
    name                   = aws_lb.platform.dns_name
    zone_id                = aws_lb.platform.zone_id
    evaluate_target_health = false
  }
}
