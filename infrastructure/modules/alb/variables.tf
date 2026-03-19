variable "vpc_id" {
  description = "VPC ID"
}

variable "subnets" {
  description = "List of subnet IDs for the ALB"
  type = list(string)
}

variable "alb_sg_id" {
  description = "ALB security group ID"
}

variable "web_server_ids" {
  type = list(string)
}

variable "environment" {
  description = "Environment name"
}