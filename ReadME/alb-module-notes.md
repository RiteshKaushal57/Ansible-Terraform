# Phase 1 — Terraform ALB Module

## What This Module Does

This module creates the Application Load Balancer and everything needed to route user traffic to your web servers. It is the public entry point of your entire application — the only thing users ever directly interact with.



## Resources Created

```
aws_alb                          → the load balancer itself
aws_alb_target_group             → the group of web servers to send traffic to
aws_alb_target_group_attachment  → registers each web server into the target group (×2)
aws_alb_listener                 → the rule that listens on port 80 and forwards traffic
```

Total: 5 resources (4 types, but target group attachment runs twice via count)

## Architecture

```
Internet
    │
    │ port 80 (HTTP)
    ↓
┌─────────────────────────────────────┐
│     ALB (internet-facing)           │
│     spans both public subnets       │
│     Public Subnet 1 (ap-south-1a)  │
│     Public Subnet 2 (ap-south-1b)  │
└─────────────────────────────────────┘
    │
    │ Listener catches port 80 traffic
    │ forwards to target group
    ↓
┌─────────────────────────────────────┐
│          Target Group               │
│   ┌─────────────┐ ┌──────────────┐ │
│   │ Web Server 1│ │ Web Server 2 │ │
│   │  port 5000  │ │  port 5000   │ │
│   └─────────────┘ └──────────────┘ │
└─────────────────────────────────────┘
```

## Complete Traffic Flow

```
Step 1 — User opens browser
         types ALB DNS name in browser
         e.g. dev-alb-123.ap-south-1.elb.amazonaws.com

Step 2 — Request hits aws_alb on port 80
         ALB is internet-facing, reachable from anywhere

Step 3 — aws_alb_listener catches the request
         it is watching port 80 for incoming traffic

Step 4 — Listener default action: forward to target group
         target group picks Web Server 1 or Web Server 2
         alternates between them (round robin)

Step 5 — Request forwarded to chosen web server on port 5000
         Node.js processes the request
         talks to MongoDB if data is needed

Step 6 — Response travels back through ALB to user
         user sees the app
```

---

## Resources Explained

### aws_alb — The Load Balancer
```
resource "aws_alb" "alb" {
  name               = "${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_sg_id]
  subnets            = var.subnets
}
```

This is the actual load balancer AWS creates and manages for you. After terraform apply AWS assigns it a public DNS name. This DNS name is the URL users open in their browser to access your app.

**Each argument:**

`name` — label to identify it in AWS console.

`internal = false` — internet-facing. Users on the internet can reach it. If true it would only be reachable from inside the VPC.

`load_balancer_type = "application"` — there are three types:
- `application` — understands HTTP/HTTPS, works at layer 7. Used for web apps
- `network` — works at TCP/UDP level, used for non-HTTP traffic
- `gateway` — used for third party security appliances
You use application because your app speaks HTTP.

`security_groups` — attaches the ALB security group which allows port 80 from anywhere. Note the square brackets — this argument expects a list even with one item.

`subnets` — ALB spans across both public subnets in different AZs. This is why you created Public Subnet 2 even though nothing else lives there. If one AZ goes down the ALB still works from the other.

---

### aws_alb_target_group — The Server Registry
```
resource "aws_alb_target_group" "web_servers" {
  name     = "${var.environment}-web-servers"
  port     = 5000
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    path                = "/health"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
  }
}
```

A container that holds the list of servers the ALB can send traffic to. Think of it as a registry of available workers. The target group itself is empty when created — servers are added through target group attachments.

**Each argument:**

`port = 5000` — the port used when forwarding traffic TO your web servers. Your Node.js app listens on port 5000 so traffic must arrive there. This is different from the listener port (80) which is what users hit externally.

Port flow:
```
User → ALB port 80 → Target Group → Web Server port 5000
```
Port 80 is the public door. Port 5000 is the internal door.

`protocol = "HTTP"` — protocol used between ALB and web servers internally.

`vpc_id` — tells AWS which VPC these target servers live in.

**The health_check block:**

The ALB constantly monitors web servers to verify they are alive. It sends HTTP GET requests to the `/health` endpoint every 30 seconds. This is the `/health` route built in Phase 0 that returns `200 OK`.

```
ALB → GET /health → Web Server → 200 OK → ALB marks server HEALTHY
ALB → GET /health → Web Server → no response → ALB marks server UNHEALTHY
```

When a server is marked unhealthy the ALB stops sending traffic to it automatically. When it recovers and passes health checks again the ALB resumes sending traffic. Users experience zero downtime.

`healthy_threshold = 2` — must pass 2 consecutive checks to be marked healthy.
`unhealthy_threshold = 3` — must fail 3 consecutive checks to be marked unhealthy.
`interval = 30` — check every 30 seconds.

Without this block the ALB uses default health check settings which may not work with your app correctly.

---

### aws_alb_target_group_attachment — Registering Servers
```
resource "aws_alb_target_group_attachment" "web_servers" {
  count            = length(var.web_server_ids)
  target_group_arn = aws_alb_target_group.web_servers.arn
  target_id        = var.web_server_ids[count.index]
  port             = 5000
}
```

Registers each web server into the target group. This resource runs twice — once for each web server — using count.

**Each argument:**

`count = length(var.web_server_ids)` — `length()` counts items in the list. Since you have 2 web server IDs, count = 2. Terraform creates this resource twice automatically. If you ever scale to 3 servers, just pass 3 IDs and this automatically creates 3 attachments.

`target_group_arn` — which target group to register this server into. ARN is Amazon Resource Name — a unique identifier for every AWS resource.

`target_id = var.web_server_ids[count.index]` — which server to register:
- First run: `web_server_ids[0]` = Web Server 1 ID
- Second run: `web_server_ids[1]` = Web Server 2 ID

`port = 5000` — port on the web server where traffic arrives.

**Why instance IDs and not IPs:**
The ALB registers targets by instance ID not IP address. This is because private IPs can change if an instance is stopped and started. Instance IDs never change. The ALB always knows how to find the right server regardless of IP changes.

---

### aws_alb_listener — The Traffic Rule
```
resource "aws_alb_listener" "http" {
  load_balancer_arn = aws_alb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.web_servers.arn
  }
}
```

The rule attached to the ALB that defines what to do with incoming traffic. Think of it as the receptionist's instruction manual.

**Each argument:**

`load_balancer_arn` — which ALB this listener belongs to.

`port = 80` — listen for traffic arriving on port 80. Browsers automatically use port 80 for HTTP URLs with no port specified.

`protocol = "HTTP"` — listen for HTTP traffic. In production you would use HTTPS (port 443) with an SSL certificate.

**The default_action block:**

`type = "forward"` — forward the traffic. Other possible types are `redirect` (e.g. HTTP to HTTPS) and `fixed-response` (return a custom message).

`target_group_arn` — forward to this target group which contains your two web servers.

---

## Why Port 80 on ALB and Port 5000 on Web Server

This confuses everyone. Here is the reason:

Port 80 is the standard HTTP port. Browsers automatically use it when you type a URL. If your ALB listened on port 5000, users would have to type:
```
http://dev-alb-123.ap-south-1.elb.amazonaws.com:5000
```

That is non-standard and ugly. Instead:
- ALB listens on port 80 (standard, clean URLs)
- ALB internally forwards to port 5000 on web servers
- Users never know port 5000 exists

The ALB translates between the public standard port and your app's internal port.

---

## What is ARN

You saw `.arn` used throughout this module. ARN stands for Amazon Resource Name. It is a globally unique identifier for every resource in AWS:

```
arn:aws:elasticloadbalancing:ap-south-1:123456789:loadbalancer/app/dev-alb/abc
     ↑           ↑                ↑           ↑                      ↑
  prefix      service           region    account ID             resource name
```

When one resource needs to reference another, it uses the ARN. Names are not unique across accounts and regions but ARNs always are.

---

## How ALB Ensures MongoDB is Never Reached

Three layers of protection:

**Layer 1 — Not in target group:**
Only web server IDs are passed to `web_server_ids`. MongoDB instance ID is never registered. ALB has no knowledge MongoDB exists.

**Layer 2 — Security group:**
MongoDB security group only allows port 27017 from web server security group. ALB security group is not in that list.

**Layer 3 — No public IP:**
MongoDB is in private subnet with no public IP. Unreachable from internet regardless.

---

## Module Inputs (variables.tf)

| Variable | Type | Description | Source |
|---|---|---|---|
| `vpc_id` | string | VPC ID for target group | VPC module output |
| `subnets` | list(string) | Both public subnet IDs for ALB | VPC module output |
| `alb_sg_id` | string | ALB security group ID | VPC module output |
| `web_server_ids` | list(string) | Both web server instance IDs | Compute module output |
| `environment` | string | Environment name for naming | terraform.tfvars |

---

## Module Outputs (outputs.tf)

| Output | Value | Used By |
|---|---|---|
| `alb_dns_name` | Public DNS of ALB | You (open in browser), Ansible (REACT_APP_API_URL), README |

---

## Root main.tf — How ALB Module is Called

```
module "alb" {
  source         = "./modules/alb"
  vpc_id         = module.vpc.vpc_id
  subnets        = [module.vpc.public_subnet_1_id, module.vpc.public_subnet_2_id]
  alb_sg_id      = module.vpc.alb_sg_id
  web_server_ids = module.compute.web_server_ids
  environment    = var.environment
}
```

Notice `subnets` is passed as a list directly in root main.tf by combining both public subnet outputs from the VPC module.

---

## Questions and Answers

### Q: What is the difference between ALB, NLB, and GLB?

ALB (Application Load Balancer) — works at HTTP/HTTPS level (layer 7). Can route based on URL paths, headers, hostnames. Used for web applications. This is what we use.

NLB (Network Load Balancer) — works at TCP/UDP level (layer 4). Extremely fast, handles millions of requests per second. Used for non-HTTP traffic like gaming, IoT, real-time streaming.

GLB (Gateway Load Balancer) — used to route traffic through third party security appliances like firewalls. Advanced use case.

### Q: Can hackers access the app through port 80?

Yes — and that is intentional. Port 80 being open is how websites work. Google and Amazon also have port 80 open. The security is not about hiding the port. It is about what you can do once you are there. Users can only see the app. They cannot SSH into servers, access MongoDB, or reach any internal ports because security groups block all of that.

### Q: Why does the ALB need two subnets in different AZs?

AWS requires ALBs to span at least two availability zones for high availability. If one AZ (data center) goes down, the ALB continues working from the other AZ. This is an AWS hard requirement — you cannot create an ALB with just one subnet.

### Q: What happens if a web server crashes?

The ALB health check detects the failure within 90 seconds (3 failed checks × 30 second interval). It marks the server unhealthy and stops sending traffic to it. All traffic goes to the remaining healthy web server. Users experience no downtime. When the crashed server recovers and passes 2 consecutive health checks, the ALB resumes sending it traffic.

### Q: What is round robin load balancing?

The default ALB algorithm. Requests are distributed evenly across all healthy targets in sequence:
```
Request 1 → Web Server 1
Request 2 → Web Server 2
Request 3 → Web Server 1
Request 4 → Web Server 2
```
This ensures neither server gets overloaded while the other sits idle.

### Q: Why is the ALB expensive compared to other resources?

ALB charges per hour plus per LCU (Load Balancer Capacity Unit) based on traffic. For a test project with minimal traffic the cost is about $0.0225 per hour — roughly $0.54 per day. Always run `terraform destroy` when done testing to avoid unnecessary charges. The NAT Gateway is actually more expensive than the ALB at $0.045 per hour.

### Q: In production would we use HTTP or HTTPS?

Always HTTPS in production. You would:
- Register a domain name
- Create an SSL certificate in AWS Certificate Manager (free)
- Change the listener to port 443 with HTTPS
- Add a second listener on port 80 that redirects to HTTPS
For this project HTTP is fine since it is a learning exercise.

---

## Total Resource Count After All Three Modules

```
VPC Module      16 resources
Compute Module   4 resources
ALB Module       5 resources
─────────────────────────────
Total           25 resources
```

This is what `terraform plan` shows before apply.
