locals {
  caller_ipv4_cidr = "${trimspace(data.http.caller_ip.response_body)}/32"
}
