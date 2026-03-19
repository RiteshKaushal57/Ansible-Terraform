variable "instance_type" {
  description = "Type of the instance"
}

variable "key_name" {
  description = "Key Pair name"
}

variable "public_subnet_1_id" {
  description = "Public subnet"
}

variable "private_subnet_id" {
  description = "Private Subnet ID"
}

variable "bastion_sg_id" {
  description = "SG ID of bastion"
}

variable "web_server_sg_id" {
  description = "SG ID of web server"
}

variable "mongodb_sg_id" {
  description = "SG ID of MongoDB"
}

variable "environment" {
  description = "Environment"
}