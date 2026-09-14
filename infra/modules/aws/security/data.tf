data "aws_vpc" "this" {
  filter {
    name   = "tag:Name"
    values = [var.vpc_name]
  }
}

data "http" "caller_ip" {
  url = "https://checkip.amazonaws.com"

  request_headers = {
    Accept = "text/plain"
  }

  lifecycle {
    postcondition {
      condition = (
        self.status_code == 200 &&
        can(cidrhost("${trimspace(self.response_body)}/32", 0)) &&
        !strcontains(trimspace(self.response_body), ":")
      )
      error_message = "checkip.amazonaws.com must return a valid public IPv4 address."
    }
  }
}
