resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
}

resource "aws_subnet" "at_public_subnet_1" {
  vpc_id = aws_vpc.main.id
  cidr_block = var.public_subnet_1_cidr
  availability_zone = var.az_1
  map_public_ip_on_launch = true # This line ensures that instances launched in this subnet will automatically receive a public IP address, allowing them to communicate with the internet.
}

resource "aws_subnet" "at_public_subnet_2" {
  vpc_id = aws_vpc.main.id
  cidr_block = var.public_subnet_2_cidr
  availability_zone = var.az_2 
  map_public_ip_on_launch = true
}

resource "aws_subnet" "at_private_subnet" {
    vpc_id = aws_vpc.main.id
    cidr_block = var.private_subnet_cidr  
    availability_zone = var.az_1
    map_public_ip_on_launch = false
}

resource "aws_internet_gateway" "ansible_terraform" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "public" {
    vpc_id = aws_vpc.main.id
    
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.ansible_terraform.id
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0" 
    nat_gateway_id = aws_nat_gateway.main.id
  }
}

resource "aws_route_table_association" "public_subnet_1" {
  subnet_id = aws_subnet.at_public_subnet_1.id 
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_subnet_2" {
  subnet_id = aws_subnet.at_public_subnet_2.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private_subnet" {
  subnet_id = aws_subnet.at_private_subnet.id
  route_table_id = aws_route_table.private.id
}

resource "aws_eip" "natgateway" { 
  domain = "vpc"

  # A static public IP address that belongs to your AWS account. It does not change even if you restart resources. The NAT Gateway needs a fixed public IP to send outbound traffic from. When your private server makes a request to the internet, it goes through NAT Gateway which uses this Elastic IP as the source address. The response comes back to this IP and NAT forwards it back to the private server. Why domain = "vpc": This tells AWS this EIP is for use inside a VPC, not for EC2-Classic
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.natgateway.id # Attaches the Elastic IP to this NAT Gateway so it has a fixed public IP to use.
  subnet_id = aws_subnet.at_public_subnet_1.id 
}

resource "aws_security_group" "alb" {
  name = "${var.environment}-alb-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "bastion" {
  name = "${var.environment}-bastion-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = [var.your_ip]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

}

resource "aws_security_group" "web_server" {
  name = "${var.environment}-web-server-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  ingress {
    from_port = 5000
    to_port = 5000
    protocol = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "mongodb" {
  name = "${var.environment}-mongodb-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port = 27017
    to_port = 27017
    protocol = "tcp"
    cidr_blocks = [aws_security_group.web_server.id]
  }

  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = [aws_security_group.bastion.id]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}