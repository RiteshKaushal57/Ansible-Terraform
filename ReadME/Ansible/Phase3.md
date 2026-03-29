# Phase 3 — Server Configuration (Ansible)

## What This Phase Is About

Terraform gave us four blank Ubuntu servers. Phase 3 is about understanding how Ansible works, why we structured everything the way we did, and what we actually created — the concepts behind playbooks, roles, tasks, modules, handlers, and templates, along with the actual files we wrote and the reason behind each one.

---

## Why Ansible?

Terraform's job ends the moment EC2 instances are running. It hands over blank Ubuntu servers and says "here, they exist." It has no idea what software should be on them.

Ansible's job starts right there. It SSHes into those blank servers and installs Node.js, installs MongoDB, copies the app code, creates the .env file, and starts the process.

```
Terraform   →   creates servers (infrastructure)
Ansible     →   configures servers (software + app)
```

The key advantage: you write the instructions once. Ansible runs them on 1 server or 100 servers with the same command. No manual SSH, no typing commands on servers one by one.

---

## How Ansible Works — The Mental Model

Ansible connects to servers over SSH and runs tasks. No agent to install on the server, no daemon running in the background. Just SSH + Python on the remote server.

```
Your Laptop
    │
    │ SSH (through bastion for private servers)
    ↓
Server
    └── Python runs each task locally
```

Every task is just Python code running on the remote server. Ansible ships with hundreds of built-in modules (apt, git, npm, service etc.) so you do not have to write raw shell commands for common operations.

---

## The Four Building Blocks

### 1. Task — The Smallest Unit

A task is one single action Ansible performs on a server. Every task has:
- A `name` — human readable description shown in output
- A `module` — the built-in function to run
- `arguments` — options for that module

```yaml
- name: Install Node.js
  apt:
    name: nodejs
    state: present
```

Read it as: "Make sure nodejs is installed using apt."

---

### 2. Module — The Tool

A module is a built-in Ansible function. Think of it as a tool in a toolbox:

| Module | What it does | Used for |
|---|---|---|
| `apt` | Install/remove packages | Install Node.js, MongoDB |
| `git` | Clone a repository | Get app code from GitHub |
| `npm` | Run npm commands | npm install, install PM2 |
| `template` | Copy file with variables filled in | Create .env file |
| `shell` | Run any shell command | npm run build, pm2 start |
| `service` | Start/stop/restart services | Start MongoDB |
| `file` | Create folders, set permissions | Create /opt/todo-app |
| `lineinfile` | Edit a specific line in a file | Change MongoDB bindIp |

---

### 3. Role — A Group of Related Tasks

A role is a folder that groups tasks doing the same job. Instead of one giant file with 50 tasks, you split them into focused, reusable roles.

Each role has a specific folder structure Ansible expects:

```
roles/nodejs/
├── tasks/
│   └── main.yml     ← list of tasks (required)
├── handlers/
│   └── main.yml     ← tasks that run when notified (optional)
└── templates/
    └── .env.j2      ← files with variables (optional)
```

The only required folder is `tasks/main.yml`. Everything else is optional.

Roles are reusable. The `common` role runs on both web servers AND the MongoDB server — same role, different servers.

---

### 4. Playbook — The Master Plan

A playbook ties everything together. It says:
- Which servers to run on (`hosts`)
- Whether to use sudo (`become`)
- Which variables to use (`vars`)
- Which roles to run in which order (`roles`)

```yaml
---
- name: Configure web servers
  hosts: webservers       ← matches [webservers] group in hosts.ini
  become: true            ← run all tasks with sudo
  vars:
    mongodb_ip: "10.0.2.221"
    alb_dns_name: "dev-alb-51613694.ap-south-1.elb.amazonaws.com"
  roles:
    - common              ← runs first
    - nodejs              ← runs second
    - app                 ← runs last
```

---

## What is Idempotent

Running a playbook 10 times gives the same result as running it once.

- Node.js not installed → Ansible installs it → output shows `changed`
- Node.js already installed → Ansible skips it → output shows `ok`

This matters because if a playbook fails halfway through, you fix the issue and rerun the whole thing. Tasks that already completed just skip themselves.

---

## What is a Handler

A handler is a special task that only runs when notified by another task. Used when a config file changes and a service needs to restart:

```yaml
# task notifies the handler
- name: Configure MongoDB to accept remote connections
  lineinfile:
    path: /etc/mongod.conf
    regexp: '  bindIp:'
    line: '  bindIp: 0.0.0.0'
  notify: restart mongodb

# handler only runs if notified
- name: restart mongodb
  service:
    name: mongod
    state: restarted
```

Without a handler, MongoDB would restart every single time the playbook runs even when the config did not change. With a handler, it only restarts when the config actually changed.

---

## What is a Template

A template is a file with Jinja2 placeholders that get filled in when Ansible runs. We used it for the `.env` file because it contains the MongoDB IP — a value that changes every time Terraform recreates the infrastructure.

```
roles/app/templates/.env.j2 (on your laptop):
────────────────────────────────────────────
PORT=5000
MONGO_URI=mongodb://{{ mongodb_ip }}:27017/todos
```

When Ansible runs, `{{ mongodb_ip }}` gets replaced with the actual value from the playbook vars:

```
/opt/todo-app/todo-app/backend/.env (created on server):
─────────────────────────────────────────────────────────
PORT=5000
MONGO_URI=mongodb://10.0.2.221:27017/todos
```

The `.j2` extension stands for Jinja2 — the templating language Ansible uses.

---

## How Variables Flow Through Ansible

Variables defined in the playbook flow into roles and templates:

```
playbooks/webservers.yml
vars:
  mongodb_ip: "10.0.2.221"          ← defined here
  alb_dns_name: "dev-alb-xxx..."    ← defined here
        ↓
roles/app/tasks/main.yml
  REACT_APP_API_URL: "http://{{ alb_dns_name }}"   ← used here
        ↓
roles/app/templates/.env.j2
  MONGO_URI=mongodb://{{ mongodb_ip }}:27017/todos  ← used here
        ↓
/opt/todo-app/todo-app/backend/.env (on server)
  MONGO_URI=mongodb://10.0.2.221:27017/todos        ← final result
```

---

## The Setup We Created

### Folder Structure

```
ansible/
├── ansible.cfg                      ← global Ansible settings
├── inventory/
│   └── hosts.ini                    ← server list and SSH config
├── playbooks/
│   ├── mongodb.yml                  ← configures MongoDB server
│   └── webservers.yml               ← configures web servers
└── roles/
    ├── common/
    │   └── tasks/
    │       └── main.yml             ← apt update + install utilities
    ├── nodejs/
    │   └── tasks/
    │       └── main.yml             ← Node.js + PM2 installation
    ├── mongodb/
    │   ├── tasks/
    │   │   └── main.yml             ← MongoDB install + config
    │   └── handlers/
    │       └── main.yml             ← restart MongoDB on config change
    └── app/
        ├── tasks/
        │   └── main.yml             ← full app deployment (Phase 4)
        └── templates/
            └── .env.j2              ← .env template with variables
```

---

### ansible.cfg — Why We Created It

```ini
[defaults]
inventory = inventory/hosts.ini
remote_user = ubuntu
private_key_file = ~/.ssh/AWS.pem
host_key_checking = False
retry_files_enabled = False
roles_path = roles
```

**Why each line:**

`inventory` — so you do not have to type `-i inventory/hosts.ini` on every command. Ansible knows where to find servers automatically.

`remote_user = ubuntu` — Ubuntu EC2 instances always use `ubuntu` as the default SSH user. Setting this globally means you do not specify it every time.

`private_key_file` — the AWS .pem key for SSH authentication. Set globally so every command uses it automatically.

`host_key_checking = False` — disables the "are you sure you want to connect?" SSH prompt. Required for automation so Ansible does not hang waiting for input.

`retry_files_enabled = False` — stops Ansible from creating `.retry` files when playbooks fail. Keeps the project folder clean.

`roles_path = roles` — tells Ansible where to find your roles folder. Without this Ansible looks in the wrong place and throws "role not found" errors.

---

### inventory/hosts.ini — Why We Created It

```ini
[bastion]
bastion-host ansible_host=52.66.25.189

[webservers]
web1 ansible_host=10.0.2.22
web2 ansible_host=10.0.2.180

[mongodb]
db ansible_host=10.0.2.221

[all:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=~/.ssh/AWS.pem

[webservers:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o ProxyCommand="ssh -W %h:%p -i /home/ritesh/.ssh/AWS.pem -o StrictHostKeyChecking=no ubuntu@52.66.25.189"'

[mongodb:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o ProxyCommand="ssh -W %h:%p -i /home/ritesh/.ssh/AWS.pem -o StrictHostKeyChecking=no ubuntu@52.66.25.189"'
```

**Why groups exist:**
- `[bastion]` — direct SSH, has public IP, no jump needed
- `[webservers]` — private subnet, must jump through bastion
- `[mongodb]` — private subnet, must jump through bastion

**Why ProxyCommand for webservers and mongodb:**
Web servers and MongoDB are in the private subnet with no public IP. Ansible cannot reach them directly. ProxyCommand tells SSH to go through bastion first, then tunnel to the private server. The bastion hop is completely transparent — Ansible behaves as if it connected directly.

**Why IPs come from Terraform outputs:**
These IPs were copied directly from `terraform output` after `terraform apply`. They change every time infrastructure is recreated so this file must be updated whenever you run `terraform destroy` and `terraform apply` again.

---

### playbooks/mongodb.yml — Why We Created It

```yaml
---
- name: Configure MongoDB server
  hosts: mongodb
  become: true
  roles:
    - common
    - mongodb
```

**Why this exists:**
MongoDB server needs different software than web servers. It needs MongoDB installed, not Node.js. Keeping it in a separate playbook means you can run it independently and it only touches the database server.

**Why run it first:**
Web servers need MongoDB running before the app can start. Always run this playbook before the webservers playbook.

**Why no vars section:**
The MongoDB server does not need `mongodb_ip` or `alb_dns_name`. It just needs to be configured. Simple and clean.

---

### playbooks/webservers.yml — Why We Created It

```yaml
---
- name: Configure web servers
  hosts: webservers
  become: true
  vars:
    mongodb_ip: "10.0.2.221"
    alb_dns_name: "dev-alb-51613694.ap-south-1.elb.amazonaws.com"
  roles:
    - common
    - nodejs
    - app
```

**Why this exists:**
Web servers need Node.js, PM2, and the deployed application. Different job from the MongoDB server so it gets its own playbook.

**Why vars are defined here:**
`mongodb_ip` fills the `{{ mongodb_ip }}` placeholder in the `.env.j2` template. `alb_dns_name` fills `{{ alb_dns_name }}` used when building the React frontend. These values are only known after Terraform runs so they live here and get updated after each `terraform apply`.

**Why roles run in this order:**
- `common` first — every server needs updated packages before anything else
- `nodejs` second — Node.js must be installed before deploying the app
- `app` last — deployment can only happen after Node.js and PM2 exist

---

### roles/common/tasks/main.yml — Why We Created It

```yaml
---
- name: Update apt cache
  apt:
    update_cache: yes

- name: Install basic utilities
  apt:
    name:
      - curl
      - git
      - wget
      - unzip
    state: present
```

**Why this role exists:**
Every server — web server, MongoDB server, bastion — needs a fresh package list and basic utilities before anything else. Running `apt update` ensures you install the latest version of packages, not a stale cached version.

**Why `state: present`:**
Install if not installed, skip if already installed. Idempotent.

---

### roles/nodejs/tasks/main.yml — Why We Created It

```yaml
---
- name: Add NodeSource repository
  shell: curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
  args:
    creates: /etc/apt/sources.list.d/nodesource.list

- name: Install Node.js
  apt:
    name: nodejs
    state: present
    update_cache: yes

- name: Install PM2 globally
  npm:
    name: pm2
    global: yes
    state: present
```

**Why add NodeSource repository first:**
Ubuntu's default apt repository has a very old Node.js version. NodeSource provides the latest LTS versions. Without adding this repository, `apt install nodejs` would install an outdated version that might not be compatible with your app.

**Why `creates: /etc/apt/sources.list.d/nodesource.list`:**
Makes the shell task idempotent. If the NodeSource list file already exists, skip running the setup script again. Without this, the shell task runs every single time.

**Why PM2:**
Node.js apps stop when the terminal closes. PM2 runs your app as a background daemon, restarts it if it crashes, and can configure it to start automatically on server reboot. Without PM2 your app would stop the moment Ansible disconnects.

---

### roles/mongodb/tasks/main.yml — Why We Created It

```yaml
---
- name: Import MongoDB GPG key
  apt_key:
    url: https://www.mongodb.org/static/pgp/server-7.0.asc
    state: present

- name: Add MongoDB repository
  apt_repository:
    repo: "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse"
    state: present

- name: Install MongoDB
  apt:
    name: mongodb-org
    state: present
    update_cache: yes

- name: Configure MongoDB to accept remote connections
  lineinfile:
    path: /etc/mongod.conf
    regexp: '  bindIp:'
    line: '  bindIp: 0.0.0.0'
  notify: restart mongodb

- name: Start MongoDB service
  service:
    name: mongod
    state: started
    enabled: yes
```

**Why add GPG key first:**
apt needs to verify that packages from the MongoDB repository are genuine and not tampered with. The GPG key is the signature it uses for verification. Without it apt refuses to install from the MongoDB repository.

**Why add MongoDB repository:**
Same reason as NodeSource — Ubuntu's default MongoDB is outdated. The official MongoDB repository provides MongoDB 7.0.

**Why `bindIp: 0.0.0.0`:**
By default MongoDB only listens on `127.0.0.1` (localhost). This means only processes on the same machine can connect to it. Your web servers are on different machines (different private IPs) so MongoDB must listen on all interfaces. The security group still restricts which servers can actually reach port 27017 — only web servers are allowed through the security group rule.

**Why `enabled: yes`:**
Makes MongoDB start automatically when the server reboots. Without this, if AWS restarts the instance, MongoDB would be stopped and your app would fail to connect.

---

### roles/mongodb/handlers/main.yml — Why We Created It

```yaml
---
- name: restart mongodb
  service:
    name: mongod
    state: restarted
```

**Why this exists:**
The `lineinfile` task that changes `bindIp` notifies this handler. MongoDB must be restarted for the config change to take effect. Using a handler instead of a regular task means MongoDB only restarts when the config actually changed — not on every playbook run.

---

### roles/app/templates/.env.j2 — Why We Created It

```
PORT=5000
MONGO_URI=mongodb://{{ mongodb_ip }}:27017/todos
```

**Why a template instead of a regular file:**
The MongoDB IP address changes every time `terraform destroy` and `terraform apply` is run. If this was a static file you would have to manually update it every deployment. With a template, Ansible fills in the current IP automatically from the playbook vars. One less manual step, one less chance of error.

**Why `mode: '0600'` when creating it:**
The .env file contains your database connection string. `0600` means only the owner (ubuntu) can read it. Other users on the server cannot see your credentials.

---

## Role Responsibilities Summary

| Role | Runs On | What It Installs/Configures |
|---|---|---|
| common | all servers | apt cache, curl, git, wget, unzip |
| nodejs | web servers | NodeSource repo, Node.js 18, PM2 |
| mongodb | mongodb server | MongoDB 7.0, bindIp config, service |
| app | web servers | full app deployment (covered in Phase 4) |

---

## Why Two Separate Playbooks

```
mongodb.yml    → runs on [mongodb] group only
webservers.yml → runs on [webservers] group only
```

Different servers need different software. MongoDB server does not need Node.js. Web servers do not need MongoDB installed. Keeping them separate means you can rerun just one if needed and it only touches the right servers.

---

## Phase 3 Completion Checklist

- [x] Understood what Ansible is and why it is used
- [x] Understood tasks, modules, roles, playbooks, handlers, templates
- [x] Understood idempotency and why it matters
- [x] Understood how variables flow from playbook into roles and templates
- [x] Created ansible.cfg with all required settings
- [x] Created hosts.ini with all 4 servers and ProxyCommand for private servers
- [x] Created common role — apt update + utilities
- [x] Created nodejs role — NodeSource + Node.js 18 + PM2
- [x] Created mongodb role — MongoDB 7.0 + bindIp config + service
- [x] Created mongodb handler — restart on config change
- [x] Created app role tasks structure (deployment in Phase 4)
- [x] Created .env.j2 template
- [x] Created mongodb.yml playbook
- [x] Created webservers.yml playbook with vars

---

## Commands Reference

```bash
# Run playbooks
ansible-playbook playbooks/mongodb.yml
ansible-playbook playbooks/webservers.yml

# Useful flags
--syntax-check     # check for syntax errors without running
--check            # dry run — shows what would change
--limit web1       # run on one specific host only

# Verify from laptop
ansible webservers -m shell -a "node --version"
ansible webservers -m shell -a "pm2 --version"
ansible mongodb -m shell -a "systemctl status mongod"
```
