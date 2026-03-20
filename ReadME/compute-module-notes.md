# Phase 1 — Terraform Compute Module

## What This Module Does

This module creates all EC2 instances (virtual servers) on AWS. It receives network and security information from the VPC module and uses it to place servers in the correct subnets with the correct security rules attached.

## Resources Created

```
Data Source: Ubuntu 22.04 AMI (fetched automatically from AWS)
├── aws_instance (bastion)       → 1 instance, public subnet 1
├── aws_instance (web_server)    → 2 instances, private subnet (using count)
└── aws_instance (mongodb)       → 1 instance, private subnet
```

Total: 4 EC2 instances

## Architecture

```
Public Subnet 1 (ap-south-1a)
└── Bastion Host
      - Has public IP (can be SSH'd from your laptop)
      - Security group: only your IP on port 22
      - Purpose: jump point to reach private servers

Private Subnet (ap-south-1a)
├── Web Server 1   ─┐
├── Web Server 2   ─┼─ Both run MERN app (frontend + backend)
│                  ─┘ Only reachable from ALB (port 5000) and bastion (port 22)
└── MongoDB Server
      - Runs only the database
      - Only reachable from web servers (port 27017) and bastion (port 22)
```

## What Runs on Each Server

### Bastion Host
No application runs here. It is purely an SSH jump point. You SSH into bastion first, then from bastion you SSH into private servers. Without bastion, private servers are completely unreachable.

### Web Server 1 and Web Server 2
Both run the complete MERN application:
- React frontend (built into static files, served by Express)
- Node.js + Express backend API on port 5000
- PM2 process manager keeping the app alive

These are NOT separate frontend and backend servers. One server handles both. This is valid and common for small to medium applications.

### MongoDB Server
Runs only MongoDB on port 27017. Nothing else. Web servers connect to it using its private IP address in the MONGO_URI environment variable.

## Key Concepts

### What is an EC2 Instance?
A virtual computer running on AWS hardware. You choose the operating system (Ubuntu 22.04), the size (t2.micro = 1 CPU, 1GB RAM), and the network location (which subnet). AWS starts the machine and gives you SSH access using your key pair.

### What is an AMI?
Amazon Machine Image. A template that contains the operating system and initial configuration for your server. Think of it as a snapshot of a clean Ubuntu installation. Every EC2 instance starts from an AMI.

AMI IDs are region-specific. Ubuntu 22.04 in ap-south-1 has a different AMI ID than the same OS in us-east-1. That is why we use a data source to fetch it automatically instead of hardcoding.

### What is a Data Source?
A data source queries AWS and fetches information without creating anything. We use it to automatically find the latest Ubuntu 22.04 AMI ID for ap-south-1:

```
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]   # Canonical = Ubuntu's official AWS account

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}
```

Then used as: `ami = data.aws_ami.ubuntu.id`

This is better than hardcoding because if AWS publishes a newer Ubuntu 22.04 patch, your next `terraform apply` automatically uses it.

### What is count?
Instead of writing two identical resource blocks for web servers, `count` creates multiple copies of one block:

```
resource "aws_instance" "web_server" {
  count = 2
  ...
  tags = {
    Name = "${var.environment}-web-server-${count.index + 1}"
  }
}
```

`count.index` is 0 for the first instance and 1 for the second. Adding +1 makes tags say web-server-1 and web-server-2 instead of web-server-0 and web-server-1.

### Why `[*]` in outputs for web servers?
Because web_server is a list of 2 instances (created with count), you cannot access a single value directly. `[*]` means "give me this attribute from ALL instances in the list":

```
output "web_server_private_ips" {
  value = aws_instance.web_server[*].private_ip
  # returns: ["10.0.2.10", "10.0.2.11"]
}
```

### Why `vpc_security_group_ids` uses square brackets?
Because this argument expects a LIST even if you only have one security group. The `_ids` (plural) at the end is your hint:

```
vpc_security_group_ids = [var.bastion_sg_id]   # correct - list with one item
vpc_security_group_ids = var.bastion_sg_id      # wrong - single value
```

## How This Module Receives Values From VPC Module

The VPC module creates security groups and subnets, then exposes their IDs through outputs. Root main.tf picks those up and passes them to the compute module:

```
modules/vpc/outputs.tf          root main.tf                modules/compute/variables.tf
──────────────────────          ────────────                ────────────────────────────
output "bastion_sg_id"          module "compute" {          variable "bastion_sg_id" {}
output "web_server_sg_id"         bastion_sg_id =
output "mongodb_sg_id"              module.vpc          →   used as var.bastion_sg_id
output "public_subnet_1_id"           .bastion_sg_id        in aws_instance resources
output "private_subnet_id"        ...
                                }
```

## Resources Explained

### Data Source — Ubuntu AMI
Queries AWS to find the latest official Ubuntu 22.04 image for the current region. Using `most_recent = true` ensures you always get the latest patched version. Owner ID `099720109477` is Canonical's official AWS account — this ensures you get genuine Ubuntu images, not third party ones.

### Bastion Instance
```
resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.public_subnet_1_id
  key_name               = var.key_name
  vpc_security_group_ids = [var.bastion_sg_id]
}
```
Placed in public subnet so it gets a public IP. The bastion security group only allows SSH from your IP. This is the only server in the entire infrastructure directly reachable from the internet.

### Web Server Instances
```
resource "aws_instance" "web_server" {
  count                  = 2
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.private_subnet_id
  key_name               = var.key_name
  vpc_security_group_ids = [var.web_server_sg_id]
}
```
Two identical servers in private subnet. Both run the same MERN app. The load balancer distributes traffic between them. If one goes down, the other keeps serving users. This is horizontal scaling.

### MongoDB Instance
```
resource "aws_instance" "mongodb" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.private_subnet_id
  key_name               = var.key_name
  vpc_security_group_ids = [var.mongodb_sg_id]
}
```
Single database server in private subnet. No public IP. Only accessible from web servers on port 27017 and bastion on port 22. In production you would use MongoDB replica sets for high availability but for this project one instance is sufficient.

---

## Module Inputs (variables.tf)

| Variable | Description | Example Value | Source |
|---|---|---|---|
| `instance_type` | EC2 size | `t2.micro` | terraform.tfvars |
| `key_name` | SSH key pair name | `ansible-terraform-key` | terraform.tfvars |
| `environment` | Environment name | `dev` | terraform.tfvars |
| `public_subnet_1_id` | Public subnet for bastion | subnet-xxxxx | VPC module output |
| `private_subnet_id` | Private subnet for servers | subnet-xxxxx | VPC module output |
| `bastion_sg_id` | Bastion security group | sg-xxxxx | VPC module output |
| `web_server_sg_id` | Web server security group | sg-xxxxx | VPC module output |
| `mongodb_sg_id` | MongoDB security group | sg-xxxxx | VPC module output |

---

## Module Outputs (outputs.tf)

| Output | Value | Used By |
|---|---|---|
| `bastion_public_ip` | Public IP of bastion | You (SSH access), Ansible inventory |
| `web_server_private_ips` | List of both web server IPs | Ansible inventory |
| `web_server_ids` | List of both web server instance IDs | ALB module (target group) |
| `mongodb_private_ip` | Private IP of MongoDB server | Ansible inventory, web server .env |

---

## Questions and Answers

### Q: Why are we not creating separate servers for frontend and backend?

Because frontend and backend are logical layers, not always physical separations. Your React frontend is built into static HTML/CSS/JS files and served by Express on the same server as your backend API. This is completely valid for small to medium applications. Large companies separate them when they need to scale each layer independently.

### Q: Why two web servers?

Two web servers allow the load balancer to distribute traffic between them. If one server crashes, the load balancer detects it through health checks and stops sending traffic to it. Users never experience downtime. This is called high availability. One server would be a single point of failure.

### Q: Why does Bastion have a public IP but web servers do not?

Bastion needs a public IP because you SSH into it directly from your laptop over the internet. Web servers do not need public IPs because users never reach them directly — they go through the Load Balancer. And you never SSH into them directly — you jump through the Bastion first. No public IP means they are completely invisible to the internet.

### Q: Why is the key pair created manually and not with Terraform?

The private key (.pem file) is generated only once at creation time. If Terraform created it, the private key would be stored in the Terraform state file in S3 — a security risk. Creating it manually means only you have the private key file. Terraform only stores the key pair NAME, not the actual key.

### Q: What happens if I lose my .pem file?

You cannot recover it. AWS does not store the private key. You would need to create a new key pair, terminate your instances, and recreate them with the new key. This is why you store the .pem file safely — never delete it while your servers are running.

## SSH Access Pattern

```
Your Laptop
    │
    │ ssh -i key.pem ubuntu@BASTION_PUBLIC_IP
    ↓
Bastion Host (public subnet)
    │
    │ ssh -i key.pem ubuntu@WEB_SERVER_PRIVATE_IP
    ↓
Web Server / MongoDB (private subnet)
```

In Ansible this is called a ProxyJump — Ansible automatically handles this two-hop SSH connection using the bastion as a jump host.

## Key Commands

```bash
# After terraform apply, get outputs
terraform output bastion_public_ip
terraform output web_server_private_ips
terraform output mongodb_private_ip

# SSH into bastion
ssh -i ~/ansible-terraform-key.pem ubuntu@BASTION_PUBLIC_IP

# SSH into web server through bastion
ssh -i ~/ansible-terraform-key.pem -J ubuntu@BASTION_PUBLIC_IP ubuntu@WEB_SERVER_PRIVATE_IP
```
