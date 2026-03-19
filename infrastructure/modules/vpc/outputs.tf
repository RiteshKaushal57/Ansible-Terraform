output "vpc_id" {
 value = aws_vpc.main.id 
}

output "at_public_subnet_1_id" {
  value = aws_subnet.at_public_subnet_1.id
}

output "at_public_subnet_2_id" {
  value = aws_subnet.at_public_subnet_2.id
}

output "at_private_subnet_id" {
  value = aws_subnet.at_private_subnet.id
}

output "alb_sg_id" {
  value = aws_security_group.alb.id
}

output "web_server_sg_id" {
  value = aws_security_group.web_server.id
}

output "mongodb_sg_id" {
  value = aws_security_group.mongodb.id
}

output "bastion_sg_id" {
  value = aws_security_group.bastion.id
}