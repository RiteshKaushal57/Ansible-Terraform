# TaskFlow — MERN Todo App

A production-ready MERN stack to-do application built for DevOps deployment practice.

## Architecture

```
frontend (React)  →  backend (Express + Node.js)  →  MongoDB
     :3000                    :5000
```

## Project Structure

```
todo-app/
├── backend/
│   ├── models/Todo.js       # Mongoose schema
│   ├── routes/todos.js      # API routes
│   ├── server.js            # Entry point
│   ├── .env.example         # Environment variable template
│   └── package.json
├── frontend/
│   ├── public/index.html
│   ├── src/
│   │   ├── api/todos.js     # Centralized API calls
│   │   ├── App.js           # Main component
│   │   ├── App.css          # Styles
│   │   └── index.js         # React entry point
│   ├── .env.example         # Environment variable template
│   └── package.json
└── README.md
```

## Local Setup

### Prerequisites
- Node.js >= 18
- MongoDB running locally

### Backend

```bash
cd backend
cp .env.example .env
npm install
npm run dev
```

Backend runs on: http://localhost:5000

### Frontend

```bash
cd frontend
cp .env.example .env
npm install
npm start
```

Frontend runs on: http://localhost:3000

## API Endpoints

| Method | Endpoint           | Description       |
|--------|--------------------|-------------------|
| GET    | /api/todos         | Get all todos     |
| POST   | /api/todos         | Create a todo     |
| PUT    | /api/todos/:id     | Toggle complete   |
| DELETE | /api/todos/:id     | Delete a todo     |
| GET    | /health            | Health check      |

## Environment Variables

### Backend `.env`
```
PORT=5000
MONGO_URI=mongodb://localhost:27017/todos
```

### Frontend `.env`
```
REACT_APP_API_URL=http://localhost:5000
```

> In production, `REACT_APP_API_URL` is set to the Load Balancer DNS name before building.

## Production Deployment

This app is designed to be deployed using:
- **Terraform** — AWS infrastructure provisioning
- **Ansible** — Server configuration and app deployment

See the infrastructure repository for deployment instructions.
