output "bastion_public_ip" {
  value = aws_instance.bastion.public_ip
}

output "web_server_private_ips" {
  value = aws_instance.web_server[*].private_ip
}

output "web_server_ids" {
  value = aws_instance.web_server[*].id
}

output "mongodb_private_ip" {
  value = aws_instance.mongodb.private_ip
}