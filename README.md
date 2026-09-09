# FoodDash — Food Ordering Application

## 1. Business Problem

FoodDash is a Bangalore based food ordering startup. The development team has built a working application running on a developer's laptop in a local development environment.

The business problem is simple — we have a working application but no infrastructure to serve real customers.

As the Associate Cloud Engineer, the job is to take this application from a developer's laptop to a production environment on AWS — securely, reliably, and with the ability to handle peak traffic during lunch and dinner hours without going down.

**Three things every cloud infrastructure decision must solve:**
- **Secure** — database must not be exposed to the internet, credentials must not be hardcoded, network access must be controlled
- **Reliable** — if one server goes down, the application must keep running, database must have automatic failover
- **Scalable** — during lunch and dinner hours when traffic spikes, infrastructure must automatically add capacity and remove it when traffic drops

---

## 2. Application Type

FoodDash is a **Microservices application**.

Each feature is built as an independent service with its own codebase, its own port, and its own responsibility. Services can be deployed, scaled, and updated independently without affecting other services.

**Services:**
- user-service
- restaurant-service
- order-service
- frontend

---

## 3. Features, Services, Ports and Tech Stack

| Layer | Service | Tech Stack | Port | Responsibility |
|---|---|---|---|---|
| Frontend | frontend | React + Vite | 3000 | Customer UI — browse restaurants, place orders, login |
| Backend | user-service | Node.js + Express | 3001 | User registration, login, JWT authentication |
| Backend | restaurant-service | Node.js + Express | 3002 | List restaurants, view menu items |
| Backend | order-service | Node.js + Express | 3003 | Place order, view order history |
| Database | PostgreSQL 15 | PostgreSQL | 5432 | Permanent storage for all services |

### Service Dependencies

**user-service**
- express, cors, bcryptjs, jsonwebtoken, pg

**restaurant-service**
- express, cors, pg

**order-service**
- express, cors, jsonwebtoken, pg

**frontend**
- react, react-dom, vite, @vitejs/plugin-react

### Database Tables

| Table | Owned By | What It Stores |
|---|---|---|
| users | user-service | id, name, email, password, created_at |
| restaurants | restaurant-service | id, name, cuisine, location, rating |
| menu_items | restaurant-service | id, restaurant_id, name, price, description |
| orders | order-service | id, user_id, restaurant_id, items, total_amount, status, created_at |

---

## 4. How Services Talk to Each Other

### Local Development Flow
```
Customer opens browser
        ↓
Frontend — port 3000
        ↓
Frontend makes direct API calls to backend services
/api/users/*         → user-service port 3001
/api/restaurants/*   → restaurant-service port 3002
/api/orders/*        → order-service port 3003
        ↓
Each service connects to PostgreSQL port 5432
        ↓
order-service calls restaurant-service internally
to validate menu items before placing order
```

### AWS Production Flow (after cloud infrastructure is built)
```
Customer opens browser
        ↓
Frontend — served from S3 + CloudFront
        ↓
Frontend makes API calls to ALB DNS
        ↓
ALB (Application Load Balancer) — single entry point
routes based on URL path
/api/users/*         → user-service target group port 3001
/api/restaurants/*   → restaurant-service target group port 3002
/api/orders/*        → order-service target group port 3003
        ↓
Each service connects to RDS PostgreSQL — private subnet port 5432
        ↓
order-service calls restaurant-service internally
```

---

## 5. Environment Variables

### Database (docker-compose local)
```
POSTGRES_DB: fooddash
POSTGRES_USER: postgres
POSTGRES_PASSWORD: postgres
```

### user-service
```
PORT: 3001
DB_HOST: db
DB_USER: postgres
DB_PASSWORD: postgres
DB_NAME: fooddash
JWT_SECRET: fooddash-secret
```

### restaurant-service
```
PORT: 3002
DB_HOST: db
DB_USER: postgres
DB_PASSWORD: postgres
DB_NAME: fooddash
```

### order-service
```
PORT: 3003
DB_HOST: db
DB_USER: postgres
DB_PASSWORD: postgres
DB_NAME: fooddash
JWT_SECRET: fooddash-secret
```

> **Cloud Engineer Note:** These values are hardcoded for local development only.
> In AWS production — DB_PASSWORD and JWT_SECRET will be stored in AWS Secrets Manager.
> DB_HOST will point to the RDS endpoint. PORT and DB_NAME will come from AWS Parameter Store.
> No credentials will ever be hardcoded in production infrastructure.

---

## 6. How to Run Locally

```bash
# Clone the repository
git clone <repo-url>
cd fooddash

# Start all services with Docker Compose
docker-compose up --build

# Services will be available at:
# Frontend        → http://localhost:3000
# user-service    → http://localhost:3001
# restaurant-service → http://localhost:3002
# order-service   → http://localhost:3003
```

---

## 7. Cloud Infrastructure — What Will Be Built on AWS

This application will be deployed on AWS with the following infrastructure:

| Phase | What Gets Built |
|---|---|
| Phase 2 | VPC, Subnets, Internet Gateway, NAT Gateway, Route Tables, Security Groups |
| Phase 3 | EC2 instances, RDS PostgreSQL, database connection |
| Phase 4A | Application Load Balancer, Target Groups, Path-based routing, Health checks |
| Phase 4B | Auto Scaling Group, Launch Template, AMI, Crash testing |
| Phase 5 | S3 Static hosting, CloudFront for frontend |
| Phase 6 | Terraform — provision entire infrastructure as code |
| Phase 7 | GitHub Actions CI/CD — automate build and deploy |

---

*Document written by: Associate Cloud Engineer*
*Purpose: Cloud infrastructure reference for FoodDash application deployment on AWS*
