terraform {
  required_providers {
    ibm = {
      source = "IBM-Cloud/ibm"
    }
  }
}


variable "group" {}
variable "remote" {}

resource "ibm_is_security_group_rule" "ingress_vpn" {
  group     = var.group
  direction = "inbound"
  remote    = var.remote
}