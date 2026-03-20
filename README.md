I just built an entire cloud infrastructure on AWS — without clicking a single button in the console. 🚀

Here's what I did:

I wrote code that automatically created 25 AWS resources in minutes:
→ A private network (VPC) with public and private subnets
→ An Internet Gateway and NAT Gateway for controlled access
→ 4 EC2 servers (bastion, 2 web servers, database)
→ Security groups that lock down every server
→ An Application Load Balancer to handle user traffic

And the best part? I ran one command — terraform apply — and AWS built everything.

Some things I learned along the way:

🔒 Private subnets are powerful. My web servers have NO public IP. Users reach them only through the Load Balancer. Hackers cannot even see them.

🔑 The Bastion Host is the only door. Want to SSH into a private server? You go through the bastion first. No exceptions.

🗄️ Remote state matters. Terraform remembers what it built using a state file. I stored mine in S3 with versioning and locking — the professional way.

⚡ Modules make everything clean. Instead of one messy file, I split everything into 3 modules: vpc, compute, alb. Each module has one job and does it well.

The infrastructure is ready. The servers are running. Next step — Ansible will configure them and deploy the actual application.

This is Phase 1 of my DevOps project: deploying a full MERN stack application on AWS using Terraform + Ansible.

More updates coming as I complete each phase. 👷

#DevOps #Terraform #AWS #InfrastructureAsCode #Learning #CloudComputing

## The Big Picture First

Before any phase, understand what you're building mentally:

You will have **3 types of servers** on AWS:
- A **Bastion host** — just a doorway for you to SSH in. Nothing else runs here.
- **Web server(s)** — your MERN app lives here (React frontend + Node/Express backend)
- **MongoDB** — can run on the same web server to keep it simple, or a separate server

And **1 load balancer** sitting in front, receiving all user traffic.

---

## Phase 0 — Build the MERN App First (Locally)

Before touching any cloud, you need a working app on your own machine.

The app will be simple but real:
- **Frontend** — React app with a to-do list (add, delete, mark complete)
- **Backend** — Express API with 3-4 routes (GET, POST, DELETE todos)
- **Database** — MongoDB storing the todos

The key thing here is **environment variables**. Your backend should not have the MongoDB connection string hardcoded. It should read from a `.env` file. This matters a lot later when Ansible configures the server.

Get it running locally first. That's your baseline.

---

## Phase 1 — Terraform: Think in Layers

When you sit down with Terraform, think of it as drawing a network diagram in code. Build it in this mental order:

**Layer 1 — The network itself**
- Create a VPC (your private cloud bubble on AWS)
- Create a public subnet (where bastion and load balancer live)
- Create a private subnet (where your web server lives)
- Attach an Internet Gateway so the public subnet can reach the internet
- Create a NAT Gateway so the private subnet can reach the internet (to download packages) but nobody from outside can reach it directly

**Layer 2 — Security rules**
- Bastion: only accepts SSH from your IP
- Web server: only accepts SSH from bastion, and app traffic from the load balancer
- Load balancer: accepts HTTP/HTTPS from anywhere

**Layer 3 — The machines**
- 1 Bastion EC2 instance in public subnet
- 1 or 2 Web server EC2 instances in private subnet

**Layer 4 — The load balancer**
- Application Load Balancer in the public subnet
- Target group pointing to your web servers
- Listener on port 80

**Layer 5 — Outputs**
- After everything is created, output the IPs and DNS so Ansible can use them

Think of Terraform state as a memory file — it remembers what it already created so it doesn't duplicate things. Store this in an S3 bucket (remote state).

---

## Phase 2 — The Bridge: Terraform → Ansible

This is a small but important thinking step.

Ansible needs to know **which servers to configure and how to reach them**. You tell it through an **inventory file**.

The flow is:
1. Terraform finishes and outputs the bastion public IP and web server private IPs
2. You (or a script) take those outputs and write them into an Ansible inventory file
3. The inventory file also tells Ansible: *"to reach the web server, jump through the bastion first"*

This SSH jump is called a **ProxyJump** — Ansible connects to bastion first, then hops to the private server through it. You never expose your web server publicly.

---

## Phase 3 — Ansible: Think in Roles

Ansible's job is to take a blank Ubuntu server and make it app-ready. Think of it as a checklist that runs automatically.

Structure your Ansible work into **roles** (separate folders of tasks):

**Role 1 — common**
Things every server needs: update packages, set timezone, install basic utilities

**Role 2 — nodejs**
Install Node.js and npm, install PM2 (the process manager that keeps your app alive even after crashes)

**Role 3 — app**
- Copy your MERN app code to the server
- Run `npm install`
- Create the `.env` file with the MongoDB connection string
- Start the app with PM2

The key mental model for Ansible is **idempotency** — if you run it 10 times, the result is the same. Tasks should check "is this already done?" before doing it again.

---

## Phase 4 — App Deployment

By the time Ansible runs the `app` role, your server should have Node.js and your code. The deployment thinking is:

- Backend runs on port 5000 (Express)
- Frontend is built (`npm run build`) and served either by Express itself or Nginx
- PM2 starts the backend and keeps it running
- The load balancer forwards port 80 traffic to port 5000 on your web servers

One important decision: **how does your React frontend talk to your backend?** In production, you can't use `localhost`. The frontend needs to call the Load Balancer's DNS name. This is an environment variable in your React app at build time.

---

## Phase 5, 6, 7 — Traffic, Security, Documentation

These are validation phases, not building phases. The thinking is:

- Can you open the ALB DNS in a browser and see your app? ✅
- Can you NOT SSH directly to the web server (only through bastion)? ✅
- Is MongoDB not exposed to the internet? ✅
- Does the app survive a server restart (PM2 handles this)? ✅
