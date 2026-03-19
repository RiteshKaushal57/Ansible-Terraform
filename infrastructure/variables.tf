variable "vpc_cidr" {
  description = "The CIDR block for the VPC"
}

variable "public_subnet_1_cidr" {
  description = "The CIDR block for public subnet 1"
}

variable "public_subnet_2_cidr" {
  description = "The CIDR block for public subnet 2"
}

variable "private_subnet_cidr" {
  description = "The CIDR block for the private subnet"
}

variable "az_1" {
  description = "The availability zone for subnet 1"
}

variable "az_2" {
  description = "The availability zone for subnet 2"
}

variable "your_ip" {
  description = "Your public IP address"
}

variable "environment" {
  description = "The environment name"
}

variable "region" {
  description = "The AWS region to deploy resources in"
}

variable "instance_type" {
  description = "Type of the instance"
}

variable "key_name" {
  description = "Key pair name"
}