# Phase 1 — Terraform VPC Module

## What This Module Does

This module creates the entire network layer of the infrastructure on AWS. Everything else — servers, load balancer, database — lives inside what this module creates. It is the foundation of the whole project.

---

## Resources Created

```
VPC
├── Public Subnet 1 (ap-south-1a)   → Bastion Host lives here
├── Public Subnet 2 (ap-south-1b)   → Empty, exists only for ALB requirement
├── Private Subnet  (ap-south-1a)   → Web Servers + MongoDB live here
├── Internet Gateway                → Door between VPC and internet
├── Elastic IP                      → Static public IP for NAT Gateway
├── NAT Gateway                     → Allows private subnet outbound internet access
├── Public Route Table              → Routes traffic to Internet Gateway
├── Private Route Table             → Routes traffic to NAT Gateway
├── Route Table Associations        → Connects subnets to their route tables
├── ALB Security Group              → Port 80 open to internet
├── Bastion Security Group          → Port 22 open to your IP only
├── Web Server Security Group       → Port 22 from bastion, port 5000 from ALB
└── MongoDB Security Group          → Port 22 from bastion, port 27017 from web servers
```

---

## Architecture

```
Internet
   │
Internet Gateway
   │
┌──────────────────────────────────┐
│           VPC 10.0.0.0/16        │
│                                  │
│  Public Subnet 1 (10.0.1.0/24)  │
│  ┌─────────┐  ┌─────────────┐   │
│  │ Bastion │  │ NAT Gateway │   │
│  └─────────┘  └─────────────┘   │
│                                  │
│  Public Subnet 2 (10.0.3.0/24)  │
│  (empty, reserved for ALB)      │
│                                  │
│  Private Subnet  (10.0.2.0/24)  │
│  ┌────────────┐  ┌───────────┐  │
│  │ Web Server │  │  MongoDB  │  │
│  │   1 + 2    │  │  Server   │  │
│  └────────────┘  └───────────┘  │
└──────────────────────────────────┘
```

---

## Variable Flow — How Values Move Through Terraform

This confuses every beginner. Here is the exact journey of one value:

```
terraform.tfvars        root variables.tf       root main.tf            module variables.tf
────────────────        ─────────────────       ────────────            ───────────────────
vpc_cidr =              variable "vpc_cidr"     module "vpc" {          variable "vpc_cidr"
"10.0.0.0/16"    →      {}                →       vpc_cidr =      →     {}
                                                   var.vpc_cidr            ↓
                                                 }                       used as
                                                                         var.vpc_cidr
                                                                         in main.tf
```

Every single variable follows this exact four station journey.

### The Two Variable Files Explained

| File | Job | Syntax |
|---|---|---|
| `variables.tf` | Declares the variable EXISTS | `variable "name" {}` block |
| `terraform.tfvars` | Sets the ACTUAL VALUE | `name = "value"` only |
| Your code | USES the variable | `var.name` |

**Rule:** If you declare a variable in `variables.tf` with a default value AND also set it in `terraform.tfvars` — the `terraform.tfvars` value always wins.

**Rule:** If you declare a variable with no default and do not set it in `terraform.tfvars` — Terraform will stop and ask you to type the value manually every time you run a command. Avoid this in real projects.

---

## Resources Explained

### VPC
```
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
}
```
Your private network bubble on AWS. Nothing inside is accessible from the internet unless explicitly allowed. Think of it as your own private data center. `cidr_block = 10.0.0.0/16` gives you 65,536 IP addresses to use across all subnets and servers.

### Public Subnet 1
```
resource "aws_subnet" "at_public_subnet_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_1_cidr
  availability_zone       = var.az_1
  map_public_ip_on_launch = true
}
```
A slice of your VPC that can reach the internet. `map_public_ip_on_launch = true` means any server created here automatically gets a public IP. Bastion host lives here because you need to SSH into it from your laptop.

### Public Subnet 2
Same as Public Subnet 1 but in a different availability zone (`ap-south-1b`). This subnet exists purely because the Application Load Balancer requires subnets in at least two different availability zones. It is an AWS hard requirement. Nothing else lives here.

---

### Private Subnet
```
resource "aws_subnet" "at_private_subnet" {
  map_public_ip_on_launch = false
}
```
Servers here have no public IP. Nobody on the internet knows they exist. Web servers and MongoDB live here. They are only reachable through the Bastion (SSH) or the Load Balancer (app traffic).

### Internet Gateway
```
resource "aws_internet_gateway" "ansible_terraform" {
  vpc_id = aws_vpc.main.id
}
```
The door between your VPC and the public internet. Without it, even servers with public IPs cannot be reached. The IGW alone does nothing — it needs a route table pointing traffic to it.

### Public Route Table
```
resource "aws_route_table" "public" {
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.ansible_terraform.id
  }
}
```
Traffic rules for public subnets. `0.0.0.0/0` means any destination. Combined: send all outbound traffic to the Internet Gateway. Without this rule, even though the IGW exists, packets do not know to use it.

### Private Route Table
```
resource "aws_route_table" "private" {
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
}
```
Traffic rules for the private subnet. Points to NAT Gateway instead of IGW. Private servers can make outbound requests (like downloading packages) but the internet cannot reach them back. NAT Gateway translates the request using its public IP, gets the response, and passes it back to the private server.

**How route tables make a subnet public or private:**
- Route pointing to IGW = public (two-way internet traffic)
- Route pointing to NAT = private (outbound only)

### Route Table Associations
Three separate resources that glue subnets to their route tables. A route table does nothing until associated with a subnet.

- Public Subnet 1  →  Public Route Table   →  traffic goes to IGW    
- Public Subnet 2  →  Public Route Table   →  traffic goes to IGW    
- Private Subnet   →  Private Route Table  →  traffic goes to NAT     

```
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
```

### Elastic IP
```
resource "aws_eip" "natgateway" {
  domain = "vpc"
}
```
A static public IP address that belongs to your AWS account. NAT Gateway needs a fixed public IP to send outbound traffic from. When private servers make internet requests, they come from this IP address. `domain = "vpc"` tells AWS this EIP is for use inside a VPC.

### NAT Gateway
```
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.natgateway.id
  subnet_id     = aws_subnet.at_public_subnet_1.id
}
```
Allows private servers to reach the internet without being reachable from the internet. Lives in the **public subnet**. It needs to be in the public subnet because it itself needs internet access to forward traffic. It is the middleman between private servers and the internet.

### Security Groups

Security groups are virtual firewalls. Everything is blocked by default. You only open what you explicitly allow.

#### Ports You Need to Know

| Port | Used For |
|------|----------|
| 22 | SSH — remote terminal access to a server |
| 80 | HTTP — normal web traffic |
| 443 | HTTPS — secure web traffic |
| 5000 | Your Node.js backend app |
| 27017 | MongoDB database |

#### Understanding Security Group Arguments

**`from_port` and `to_port`** — defines a range of ports to allow. When both are the same, exactly one port is allowed:
```
from_port = 22
to_port   = 22   # exactly port 22 only
```

**`protocol`**
- `"tcp"` — used by HTTP, HTTPS, SSH, MongoDB. Guarantees reliable delivery
- `"-1"` — all protocols. Used in egress to allow all outbound traffic

**`cidr_blocks`** — used when the source is an IP address range:
```
cidr_blocks = ["0.0.0.0/0"]          # anyone on the internet
cidr_blocks = ["103.45.67.89/32"]    # one specific IP only
```

**`security_groups`** — used when the source is another security group (more secure than IP-based):
```
security_groups = [aws_security_group.bastion.id]
# only traffic coming from instances in the bastion security group
```

#### The Security Chain

```
Internet
   ↓ port 80 (open to all)
ALB Security Group
   ↓ port 5000 (only from ALB SG)
Web Server Security Group
   ↓ port 27017 (only from Web Server SG)
MongoDB Security Group

Your Laptop
   ↓ port 22 (only your IP)
Bastion Security Group
   ↓ port 22 (only from Bastion SG)
Web Server Security Group
   ↓ port 22 (only from Bastion SG)
MongoDB Security Group
```

## Questions and Answers

### Q: Subnets and servers — is it one subnet per server?

No. A subnet is a network zone that can hold many servers. Think of a subnet as a neighbourhood and servers as houses. One neighbourhood can have many houses. You do not build a new neighbourhood for every house.

In this project:
- Public Subnet 1 holds the Bastion
- Public Subnet 2 is empty (exists for ALB)
- Private Subnet holds 2 web servers AND the MongoDB server

---

### Q: What is a web server?

A web server is just a regular EC2 instance (computer) running your application. In this project it is a plain Ubuntu machine running your Node.js backend on port 5000. The term web server does not mean special hardware — it just means a server whose job is to serve web requests.

---

### Q: Why is the frontend in a private subnet? Should it not be in the public subnet so users can access it?

Being accessible to the internet does NOT mean the server must be in a public subnet. These are two separate concerns.

Users access your frontend through the **Load Balancer** which is in the public subnet. The Load Balancer forwards requests to your web server in the private subnet. Users never talk to your web server directly — they only talk to the ALB.

```
User → ALB (public subnet, port 80) → Web Server (private subnet, port 5000)
```

Keeping the web server in a private subnet means:
- No direct SSH attempts from the internet
- No port scanning of your app
- No one can bypass the load balancer
- Only controlled, specific traffic reaches your server

The Load Balancer IS your public frontend. The web server just processes requests behind it.

---

### Q: Hackers can also send requests to port 80 on the ALB. How is that safe?

You are right — anyone can hit port 80 including hackers. That is intentional. That is how all websites work. Google and Amazon also have port 80 open.

The security is not about hiding port 80. It is about what you can do once you are there.

**Through port 80 a hacker can:**
- See your app frontend ✅ (any user can do this — that is fine)
- Send API requests ✅ (any user can do this — that is fine)

**What a hacker cannot do:**
- SSH into your server ❌ — no public IP, blocked by security group
- Access MongoDB directly ❌ — port 27017 not open to anyone except web servers
- Access other ports on web server ❌ — only port 5000 allowed from ALB
- Bypass ALB and hit web server directly ❌ — web server has no public IP

The real threats (SSH takeover, database access, internal port access) are all blocked. Port 80 being open is by design.

In production, additional layers are added: HTTPS, WAF (Web Application Firewall), rate limiting, authentication on API routes.

### Q: Why does egress allow all outbound traffic even on MongoDB?

MongoDB needs to reach the internet for package installation when Ansible configures it (apt install mongodb). Without outbound access, Ansible cannot install anything. The server reaches the internet through NAT Gateway which is already restricted to outbound only.

The real protection for MongoDB is its **ingress rules** — nobody can reach INTO it except web servers on port 27017 and bastion on port 22. Outbound traffic from a database is not the threat. Unauthorized inbound access is.

## Module Inputs (variables.tf)

| Variable | Description | Example Value |
|---|---|---|
| `vpc_cidr` | IP range for the VPC | `10.0.0.0/16` |
| `public_subnet_1_cidr` | IP range for public subnet 1 | `10.0.1.0/24` |
| `public_subnet_2_cidr` | IP range for public subnet 2 | `10.0.3.0/24` |
| `private_subnet_cidr` | IP range for private subnet | `10.0.2.0/24` |
| `az_1` | First availability zone | `ap-south-1a` |
| `az_2` | Second availability zone | `ap-south-1b` |
| `environment` | Environment name for tagging | `dev` |
| `your_ip` | Your IP for SSH access to bastion | `103.x.x.x/32` |

---

## Module Outputs (outputs.tf)

| Output | Used By |
|---|---|
| `vpc_id` | Compute module, ALB module |
| `public_subnet_1_id` | Compute module (bastion), ALB module |
| `public_subnet_2_id` | ALB module |
| `private_subnet_id` | Compute module (web servers, MongoDB) |
| `bastion_sg_id` | Compute module |
| `web_server_sg_id` | Compute module |
| `mongodb_sg_id` | Compute module |
| `alb_sg_id` | Compute module, ALB module |

---

## Commands Used

```bash
# Create folder structure
mkdir -p infrastructure/{modules/vpc,modules/compute,modules/alb}
touch infrastructure/{main.tf,variables.tf,outputs.tf,terraform.tfvars,backend.tf,provider.tf}
touch infrastructure/modules/vpc/{main.tf,variables.tf,outputs.tf}

# Find your IP for terraform.tfvars
curl ifconfig.me

# Terraform workflow
terraform init      # download providers, initialize backend
terraform plan      # dry run, shows what will be created
terraform apply     # creates the infrastructure
terraform destroy   # tears everything down
```

---

## Key Concepts to Remember

**Terraform init** must be run after adding any new module or provider. It downloads required plugins.

**Terraform plan** is always run before apply. It shows exactly what will be created, changed, or destroyed. Never skip this.

**Module flow:** tfvars → root variables.tf → root main.tf → module variables.tf → module main.tf → module outputs.tf → root outputs.tf

**You do not memorize resource arguments.** You look them up at `registry.terraform.io` every time. What you memorize is concepts — what each resource IS and WHY it exists.
