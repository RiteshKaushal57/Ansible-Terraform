# Phase 4 — Application Deployment

## What This Phase Is About

Phase 3 gave us configured servers — Node.js, PM2, and MongoDB installed. Phase 4 is where we actually deployed the MERN application. This phase covers the full journey — what we tried, what broke, why it broke, how we fixed it, and the final updated version of every file that made everything work.

---

## What Deployment Means

Deployment transforms source code into a running application:

```
Source code on GitHub
        ↓
Cloned onto web servers
        ↓
Dependencies installed
        ↓
Environment variables configured
        ↓
Frontend compiled into static files
        ↓
Backend started as background process
        ↓
Load balancer routes traffic to it
        ↓
Users can access the app
```

Every step is automated by the `app` role. But getting there required fixing several real issues.

---

## Issues We Faced and How We Fixed Them

### Issue 1 — PM2 Root Process Conflict

**What happened:**
The playbook had `become: true` at the top level which caused ALL tasks to run as root — including PM2. This created a root-owned node process holding port 5000. When ubuntu's PM2 tried to start the app it kept crashing:

```
Error: listen EADDRINUSE: address already in use :::5000
```

PM2 status showed `errored` with dozens of restart attempts.

**How we debugged:**
```bash
sudo lsof -i :5000
# node\x20/ 12847 root ← owned by ROOT, not ubuntu
```

**The fix:**
Add `become_user: ubuntu` to PM2 tasks. This overrides `become: true` for those specific tasks only. Everything else still runs as root, but PM2 runs as ubuntu.

```yaml
- name: Start application with PM2
  shell: pm2 start server.js --name todo-app || pm2 restart todo-app
  become: true
  become_user: ubuntu        ← overrides playbook-level become: true
```

---

### Issue 2 — Git Dubious Ownership Error

**What happened:**
After fixing the PM2 issue, the git clone task failed:

```
fatal: detected dubious ownership in repository at '/opt/todo-app'
```

The directory was previously created and owned by root. When clone switched to run as ubuntu, Git detected the mismatch and refused.

**The fix:**
Add two tasks before the clone task — fix ownership and register the safe directory:

```yaml
- name: Fix ownership of app directory
  file:
    path: /opt/todo-app
    state: directory
    owner: ubuntu
    group: ubuntu
    recurse: yes

- name: Add git safe directory
  shell: git config --global --add safe.directory /opt/todo-app
  become: true
  become_user: ubuntu
```

---

### Issue 3 — MONGO_URI Missing from .env

**What happened:**
The `.env` file on the server only had:
```
PORT=5000
```
`MONGO_URI` was missing. App could not connect to MongoDB.

**Why:**
The template variable `{{ mongodb_ip }}` was empty because it was not declared in the playbook vars.

**The fix:**
Declare it explicitly in `playbooks/webservers.yml` and add `force: yes` to always recreate the file:

```yaml
vars:
  mongodb_ip: "10.0.2.221"
  alb_dns_name: "dev-alb-51613694.ap-south-1.elb.amazonaws.com"
```

```yaml
- name: Create backend .env file
  template:
    src: .env.j2
    dest: /opt/todo-app/todo-app/backend/.env
    owner: ubuntu
    mode: '0600'
    force: yes        ← always recreate, never skip
```

---

### Issue 4 — MongoDB Refusing Remote Connections

**What happened:**
```
MongooseServerSelectionError: connect ECONNREFUSED 10.0.2.221:27017
```

**Why:**
MongoDB only listens on `127.0.0.1` by default. Web servers on different machines could not reach it.

**The fix:**
Changed `bindIp` in the MongoDB config using `lineinfile` and added a handler to restart MongoDB when the config changes:

```yaml
- name: Configure MongoDB to accept remote connections
  lineinfile:
    path: /etc/mongod.conf
    regexp: '  bindIp:'
    line: '  bindIp: 0.0.0.0'
  notify: restart mongodb
```

---

### Issue 5 — React Serving 404 on Root Route

**What happened:**
ALB was reachable, Express was responding, but returning:
```
Cannot GET /
```

**Why:**
Express had no instruction to serve the React static files. The `build/` folder existed on the server but nothing pointed to it.

**The fix:**
Added static file serving to `server.js` with the correct route order:

```javascript
app.get('/health', ...);          // 1. health check first
app.use('/api/todos', ...);       // 2. API routes
app.use(express.static(...));     // 3. static files
app.get('*', ...);                // 4. catch all — MUST be last
```

Route order matters — Express matches top to bottom. If `app.get('*')` is placed before API routes, it catches everything and API calls never reach their handlers.

---

### Issue 6 — Wrong Frontend Build Path

**What happened:**
```
Error: ENOENT: no such file or directory, stat '/opt/todo-app/frontend/build/index.html'
```

**Why:**
The path `../../frontend/build` was wrong.

```
__dirname = /opt/todo-app/todo-app/backend
../../    = /opt/todo-app/          ← wrong, skips todo-app folder
../       = /opt/todo-app/todo-app/ ← correct
```

**The fix:**
```javascript
// Wrong
path.join(__dirname, '../../frontend/build')

// Correct
path.join(__dirname, '../frontend/build')
```

---

## The Final Updated Files

### roles/app/tasks/main.yml — Final Version

```yaml
---
- name: Create app directory
  file:
    path: /opt/todo-app
    state: directory
    owner: ubuntu
    mode: '0755'

- name: Fix ownership of app directory
  file:
    path: /opt/todo-app
    state: directory
    owner: ubuntu
    group: ubuntu
    recurse: yes

- name: Add git safe directory
  shell: git config --global --add safe.directory /opt/todo-app
  become: true
  become_user: ubuntu

- name: Clone application repository
  git:
    repo: https://github.com/RiteshKaushal57/Ansible-Terraform.git
    dest: /opt/todo-app
    version: main
    force: yes
  become: true
  become_user: ubuntu

- name: Install backend dependencies
  npm:
    path: /opt/todo-app/todo-app/backend

- name: Create backend .env file
  template:
    src: .env.j2
    dest: /opt/todo-app/todo-app/backend/.env
    owner: ubuntu
    mode: '0600'
    force: yes

- name: Install frontend dependencies
  npm:
    path: /opt/todo-app/todo-app/frontend

- name: Build React frontend
  shell: npm run build
  args:
    chdir: /opt/todo-app/todo-app/frontend
  environment:
    REACT_APP_API_URL: "http://{{ alb_dns_name }}"

- name: Start application with PM2
  shell: pm2 start server.js --name todo-app || pm2 restart todo-app
  args:
    chdir: /opt/todo-app/todo-app/backend
  become: true
  become_user: ubuntu

- name: Save PM2 process list
  shell: pm2 save
  become: true
  become_user: ubuntu

- name: Configure PM2 startup
  shell: env PATH=$PATH:/usr/bin pm2 startup systemd -u ubuntu --hp /home/ubuntu
  become: true
  ignore_errors: yes
```

---

### roles/app/templates/.env.j2 — Final Version

```
PORT=5000
MONGO_URI=mongodb://{{ mongodb_ip }}:27017/todos
```

---

### roles/mongodb/tasks/main.yml — Final Version

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

---

### roles/mongodb/handlers/main.yml — Final Version

```yaml
---
- name: restart mongodb
  service:
    name: mongod
    state: restarted
```

---

### todo-app/backend/server.js — Final Version

```javascript
require('dotenv').config();
const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
const path = require('path');

const todoRoutes = require('./routes/todos');

const app = express();

// Middleware
app.use(cors());
app.use(express.json());

// 1. Health check first — for ALB health monitoring
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'OK' });
});

// 2. API routes
app.use('/api/todos', todoRoutes);

// 3. Serve React static files
app.use(express.static(path.join(__dirname, '../frontend/build')));

// 4. Catch all — MUST be last
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, '../frontend/build', 'index.html'));
});

// MongoDB Connection
const MONGO_URI = process.env.MONGO_URI || 'mongodb://localhost:27017/todos';
const PORT = process.env.PORT || 5000;

mongoose
  .connect(MONGO_URI)
  .then(() => {
    console.log('Connected to MongoDB');
    app.listen(PORT, () => {
      console.log(`Server running on port ${PORT}`);
    });
  })
  .catch((err) => {
    console.error('MongoDB connection error:', err);
    process.exit(1);
  });
```

---

## Why React Builds on the Server

React needs to know the API URL at build time — it gets baked into the JavaScript bundle. The API URL is the ALB DNS name which only exists after Terraform creates the infrastructure. You cannot know this URL before deployment.

```
Build time:
REACT_APP_API_URL = http://dev-alb-51613694.ap-south-1.elb.amazonaws.com
        ↓
Baked into React bundle during npm run build
        ↓
Frontend always calls this URL for API requests
```

---

## Key Lessons Learned

**`become: true` runs ALL tasks as root** — be careful which tasks need root. Use `become_user` to override for specific tasks like PM2.

**File ownership matters in Linux** — directories owned by root cause tools like Git to refuse when accessed as another user. Always set correct ownership.

**Express route order is critical** — catch-all routes must always be last. First match wins.

**Always verify paths on the actual server** — SSH in and check with `ls` before assuming a path is correct.

**Debug with logs first:**
```bash
pm2 logs todo-app --lines 50 --nostream   # what is the app saying
sudo lsof -i :5000                         # what is using this port
curl http://localhost:5000/health          # is app responding
cat /opt/todo-app/todo-app/backend/.env   # are env vars correct
```

---

## Phase 4 Completion Checklist

- [x] App directory created with ubuntu ownership
- [x] Git safe directory configured
- [x] Code cloned from GitHub as ubuntu user
- [x] Backend npm dependencies installed
- [x] .env file created with correct MongoDB URI
- [x] Frontend npm dependencies installed
- [x] React built with ALB DNS name embedded
- [x] App started with PM2 as ubuntu user
- [x] PM2 process list saved
- [x] PM2 configured to start on boot
- [x] MongoDB accepting remote connections
- [x] Express serving React static files
- [x] Express route order correct
- [x] Health check returning 200 OK
- [x] ALB target group showing healthy
- [x] App accessible via ALB DNS in browser
- [x] Add, complete, delete todos all working
- [x] Data persists after page refresh
