resource "aws_security_group" "platform" {
  name        = "${var.base_name}-platform"
  description = "Public web ingress for the development platform host"
  vpc_id      = data.aws_vpc.this.id

  ingress {
    description = "Caddy HTTP redirect ingress"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [local.caller_ipv4_cidr]
  }

  ingress {
    description = "Caddy HTTPS ingress"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [local.caller_ipv4_cidr]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_security_group" "postgres" {
  name        = "${var.base_name}-postgres"
  description = "Private PostgreSQL access from the development platform host"
  vpc_id      = data.aws_vpc.this.id

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_vpc_security_group_ingress_rule" "postgres_from_platform" {
  security_group_id            = aws_security_group.postgres.id
  referenced_security_group_id = aws_security_group.platform.id
  description                  = "PostgreSQL from the platform EC2 instance only"
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}
