terraform {
  required_providers {
    ibm = {
      source = "IBM-Cloud/ibm"
    }
  }
}


variable "vsi_name" {}
variable "image" {}
variable "profile" {}
variable "vpc" {}
variable "zone" {}
variable "keys" {}
variable "user_data" {}
variable "resource_group" {}
variable "tags" {}
variable "subnet_id" {}
variable "security_group" {}


resource "ibm_is_instance" "login" {
  name           = var.vsi_name
  image          = var.image
  profile        = var.profile
  vpc            = var.vpc
  zone           = var.zone
  keys           = var.keys
  user_data      = var.user_data
  resource_group = var.resource_group
  tags           = var.tags

  # fip will be assinged
  primary_network_interface {
    name            = "eth0"
    subnet          = var.subnet_id
    security_groups = var.security_group
  }
}

output "primary_network_interface" {
  value = ibm_is_instance.login.primary_network_interface[0].id
}

output "login_id" {
  value = ibm_is_instance.login.id
}