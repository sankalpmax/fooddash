# FoodDash

FoodDash is a portfolio project for a food-ordering application. It contains a React frontend, three Node.js/Express services, and a PostgreSQL database. It is a learning project, not a commercial product or a production-ready service.

## Project status

- The application and Docker Compose setup are prototypes.
- The GitHub Actions workflow on `feature/docker-cicd-1` is experimental. It builds and publishes container images and invokes an AWS sandbox deployment; it is not a production release pipeline.
- The workflow's vulnerability scans are currently informational and do not block a deployment.
- Authentication, authorization, input validation, database TLS, and deployment secret handling need further security work before any production use.
- AWS infrastructure and application deployment status can change. The Terraform repository documents the infrastructure code separately.

## Architecture

```text
Browser
  └── React + Vite frontend (port 3000)
        ├── user-service       (port 3001)
        ├── restaurant-service (port 3002)
        └── order-service      (port 3003)
              └── PostgreSQL 15 (port 5432)
```

The services use a shared PostgreSQL database in this prototype. The frontend calls each service through `/api/users`, `/api/restaurants`, and `/api/orders` routes. The `order-service` stores order items as JSON and includes basic JWT-protected order endpoints.

| Component | Stack | Responsibility |
|---|---|---|
| `frontend/` | React, Vite | Browse restaurants, register/login, and interact with orders |
| `user-service/` | Express, PostgreSQL, bcrypt, JWT | Registration and login |
| `restaurant-service/` | Express, PostgreSQL | Restaurant and menu reads |
| `order-service/` | Express, PostgreSQL, JWT | Create and view a user's orders |
| `docker-compose.yml` | Docker Compose, PostgreSQL 15 | Local development environment |

## Run locally

Requirements: Docker Engine and the Docker Compose plugin.

```bash
docker compose up --build
```

Open the frontend at <http://localhost:3000>. The Compose configuration points the frontend at the locally exposed API services. To stop the containers, run:

```bash
docker compose down
```

The database volume is retained by default. To remove local database data too, run `docker compose down --volumes`.

The credentials in `docker-compose.yml` are demo-only local defaults. Do not reuse them outside a disposable development environment.

## Repository layout

```text
.
├── .github/workflows/fooddash-ci.yml
├── frontend/
├── order-service/
├── restaurant-service/
├── user-service/
├── scripts/deploy.sh
└── docker-compose.yml
```

## CI/CD status

The current workflow is tied to the `feature/docker-cicd-1` branch and targets an AWS sandbox. It uses repository-configured AWS credentials and an SSM-based deployment script. It is work in progress: security scanning does not fail the build, and the workflow does not provide a reviewed, protected production release process. Do not use it to deploy a production workload.

## Related project

The separate [`fooddash-infra`](https://github.com/sankalpmax/fooddash-infra) repository contains Terraform examples for AWS infrastructure. Its directory and branch names are not a claim that the system is production-ready.
