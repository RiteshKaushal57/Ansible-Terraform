# MERN Stack Deployment on AWS — Terraform + Ansible

A production-grade deployment of a MERN (MongoDB, Express, React, Node.js) todo application on AWS, built entirely with Infrastructure as Code and Configuration Management.

> Built as a hands-on DevOps project to demonstrate real-world skills in cloud infrastructure, automation, and secure deployment practices.


## What This Project Does

This project takes a MERN todo application and deploys it on AWS in the way real production systems are built:

- Infrastructure is **not created manually** — it is provisioned using Terraform
- Servers are **not configured manually** — they are configured using Ansible
- Application is **not exposed directly** — traffic flows through a Load Balancer
- Servers are **not publicly accessible** — they are secured inside private networks


## Architecture

```
User
  │
  │ HTTP port 80
  ▼
Application Load Balancer (public subnet)
  │
  │ port 5000 (round robin)
  ├──────────────────┐
  ▼                  ▼
Web Server 1      Web Server 2        (private subnet)
  │                  │
  └────────┬─────────┘
           │ port 27017
           ▼
     MongoDB Server                   (private subnet)

Admin access:
Your Laptop → Bastion Host → Private Servers
              (public)       (SSH only via bastion)
```



## Project Structure

```
Ansible-Terraform/
├── todo-app/                    # MERN application
│   ├── backend/                 # Node.js + Express API
│   └── frontend/                # React frontend
│
├── terraform/                   # Infrastructure as Code
│   ├── provider.tf
│   ├── backend.tf               # Remote state (S3)
│   ├── main.tf                  # Root orchestrator
│   ├── variables.tf
│   ├── outputs.tf
│   ├── terraform.tfvars
│   ├── backend/                 # Bootstrap (S3 + DynamoDB)
│   └── modules/
│       ├── vpc/                 # Network layer
│       ├── compute/             # EC2 instances
│       └── alb/                 # Load balancer
│
└── ansible/                     # Configuration Management
    ├── ansible.cfg
    ├── inventory/
    │   └── hosts.ini            # Server inventory
    ├── playbooks/
    │   ├── webservers.yml       # Web server playbook
    │   └── mongodb.yml          # MongoDB playbook
    └── roles/
        ├── common/              # Base system setup
        ├── nodejs/              # Node.js + PM2
        ├── mongodb/             # MongoDB installation
        └── app/                 # Application deployment
```


## Infrastructure Details

### AWS Resources (25 total)

| Resource | Count | Purpose |
|---|---|---|
| VPC | 1 | Private network — 10.0.0.0/16 |
| Public Subnet | 2 | Bastion host + ALB requirement |
| Private Subnet | 1 | Web servers + MongoDB |
| Internet Gateway | 1 | Public internet access |
| NAT Gateway | 1 | Private subnet outbound only |
| Elastic IP | 1 | Static IP for NAT Gateway |
| Route Tables | 2 | Public (IGW) + Private (NAT) |
| Route Table Associations | 3 | Subnet to route table links |
| Security Groups | 4 | ALB, Bastion, Web Server, MongoDB |
| EC2 Instances | 4 | Bastion, 2x Web Server, MongoDB |
| Application Load Balancer | 1 | Internet-facing traffic entry |
| Target Group | 1 | Web server pool with health checks |
| Target Group Attachments | 2 | Web server registrations |
| ALB Listener | 1 | Port 80 forwarding rule |

### Security Groups — Access Chain

```
ALB Security Group
  inbound:  port 80 from 0.0.0.0/0
  outbound: all

Bastion Security Group
  inbound:  port 22 from your IP only
  outbound: all

Web Server Security Group
  inbound:  port 22 from bastion SG
  inbound:  port 5000 from ALB SG
  outbound: all

MongoDB Security Group
  inbound:  port 22 from bastion SG
  inbound:  port 27017 from web server SG
  outbound: all
```

Every access path is enforced. Nothing can skip a step.

### Remote State

Terraform state is stored remotely in S3 with:
- Versioning enabled (recover from accidental changes)
- Server-side encryption (AES-256)
- Public access blocked
- DynamoDB state locking (prevents concurrent modifications)


## Application Details

### Stack
- **Frontend** — React 18, served as static files by Express
- **Backend** — Node.js + Express REST API
- **Database** — MongoDB 7.0
- **Process Manager** — PM2 (keeps app alive, auto-restarts on crash)

### API Endpoints

| Method | Endpoint | Description |
|---|---|---|
| GET | /api/todos | Fetch all todos |
| POST | /api/todos | Create a todo |
| PUT | /api/todos/:id | Toggle complete |
| DELETE | /api/todos/:id | Delete a todo |
| GET | /health | ALB health check |

### Why React Builds on the Server

React needs to know the API URL at build time — it gets baked into the JavaScript bundle. The API URL is the ALB DNS name which only exists after Terraform creates the infrastructure. So the build happens during Ansible deployment with the real URL injected as an environment variable.


## Ansible Roles

| Role | Runs On | What It Does |
|---|---|---|
| common | all servers | apt update, install utilities |
| nodejs | web servers | Node.js 18, npm, PM2 |
| mongodb | mongodb server | MongoDB 7.0, bindIp config, service |
| app | web servers | clone repo, npm install, build React, start with PM2 |



## How to Deploy

### Prerequisites

- AWS account with IAM user and programmatic access
- AWS CLI configured (`aws configure`)
- Terraform installed
- Ansible installed
- SSH key pair created in AWS console (ap-south-1)

### Step 1 — Create Remote State Backend

```bash
cd terraform/backend
terraform init
terraform apply
```

### Step 2 — Provision Infrastructure

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Fill in your values: region, your_ip, key_name etc.
terraform init
terraform plan
terraform apply
```

Note the outputs — you will need them for Ansible.

### Step 3 — Update Ansible Inventory

Edit `ansible/inventory/hosts.ini` with IPs from terraform output:

```ini
[bastion]
bastion-host ansible_host=BASTION_PUBLIC_IP

[webservers]
web1 ansible_host=WEB_SERVER_1_PRIVATE_IP
web2 ansible_host=WEB_SERVER_2_PRIVATE_IP

[mongodb]
db ansible_host=MONGODB_PRIVATE_IP
```

### Step 4 — Update Playbook Variables

Edit `ansible/playbooks/webservers.yml`:

```yaml
vars:
  mongodb_ip: "MONGODB_PRIVATE_IP"
  alb_dns_name: "YOUR_ALB_DNS_NAME"
```

### Step 5 — Deploy Application

```bash
cd ansible
ansible all -m ping                          # verify connectivity
ansible-playbook playbooks/mongodb.yml       # configure database first
ansible-playbook playbooks/webservers.yml    # configure web servers
```

### Step 6 — Access the App

Open in browser:
```
http://YOUR_ALB_DNS_NAME
```

### Step 7 — Destroy When Done

```bash
cd terraform
terraform destroy
```

Always destroy when finished to avoid AWS charges.



## Key Design Decisions

**Why private subnet for web servers?**
Web servers do not need public IPs. Users reach them through the ALB. Keeping them private means they are invisible to the internet — no port scanning, no direct SSH attempts, no bypass of the load balancer.

**Why a Bastion host?**
The only way to SSH into private servers. One hardened entry point instead of exposing every server. Only your IP can reach it on port 22.

**Why two web servers?**
High availability. If one server crashes the ALB detects it through health checks and routes all traffic to the other. Users experience zero downtime.

**Why MongoDB on a separate server?**
Separation of concerns. Database and application have different resource needs and security profiles. Keeping them separate means a compromised app server cannot directly access the database filesystem.

**Why NAT Gateway in the public subnet?**
Private servers need outbound internet access to download packages. NAT Gateway allows outbound-only traffic — it translates private IPs to its public Elastic IP for outbound requests but blocks all incoming connections.

**Why Terraform modules?**
Each module owns a clear domain — vpc, compute, alb. Changes to one module do not affect others. Outputs flow cleanly from one module to the next. Reflects how real teams organize infrastructure code.



## Tools Used

| Tool | Version | Purpose |
|---|---|---|
| Terraform | >= 1.0 | Infrastructure provisioning |
| Ansible | >= 2.14 | Server configuration and deployment |
| AWS | — | Cloud provider |
| Node.js | 18 | Backend runtime |
| MongoDB | 7.0 | Database |
| PM2 | latest | Process management |
| React | 18 | Frontend framework |



## Cost Estimate

Running this infrastructure costs approximately:

| Resource | Cost/hour |
|---|---|
| NAT Gateway | $0.045 |
| ALB | $0.0225 |
| EC2 t2.micro × 4 | $0.046 |
| **Total** | **~$0.11/hour** |

Always run `terraform destroy` when done. Leaving it running overnight costs ~$2.60.



## Project Documentation

Detailed notes for each phase are in the `ReadME/` folder:

- `vpc-module-notes.md` — VPC networking explained
- `compute-module-notes.md` — EC2 instances and modules
- `alb-module-notes.md` — Load balancer configuration
- `state-locking-notes.md` — Remote state and S3 backend
- `phase1-readme.md` — Full Terraform phase documentation
- `phase2-readme.md` — Ansible inventory and SSH ProxyJump
- `Phase3.md` — Ansible roles and playbooks
- `Phase4.md` — Application deployment
- `Phase4.md` — Debugging and lessons learned



## What I Learned

This project taught me how infrastructure, configuration, and application deployment connect in a real production system. Key takeaways:

- Infrastructure as Code makes environments reproducible and version controlled
- Private subnets and security group chains are how production systems stay secure
- Ansible roles separate concerns cleanly — one role, one job
- Real deployments always hit unexpected issues (PM2 root conflicts, path mismatches, MongoDB bind config) — debugging is a core skill
- Documentation is as important as the code itself