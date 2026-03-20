output "bastion_public_ip" {
  value = module.compute.bastion_public_ip
}

output "web_server_private_ips" {
  value = module.compute.web_server_private_ips
}

output "mongodb_private_ip" {
  value = module.compute.mongodb_private_ip
}

output "alb_dns_name" {
  value = module.alb.alb_dns_name
}