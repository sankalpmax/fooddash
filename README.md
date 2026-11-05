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

## CI/CD pipeline

The workflow lives at `.github/workflows/fooddash-ci.yml` and triggers on push to `feature/docker-cicd-1`. It targets an AWS sandbox in `ap-south-2`, not a production environment.

```text
Push to feature/docker-cicd-1
        │
        ├──► JOB 1: user-service        ─┐
        ├──► JOB 2: restaurant-service   ─┤
        ├──► JOB 3: order-service         ─┤  (4 jobs run in parallel)
        └──► JOB 4: frontend              ─┘
                │
                │  1. Checkout code
                │  2. Configure AWS credentials (IAM keys from repo secrets)
                │  3. Login to Amazon ECR
                │  4. Build Docker image (tagged with commit SHA)
                │  5. Trivy scan — CRITICAL + HIGH only
                │     └─ exit-code: 0 → findings do NOT block the build
                │  6. Push image to ECR
                │
                ▼
        JOB 5: deploy (runs only after all 4 builds succeed)
                │
                │  1. Checkout code + configure AWS credentials
                │  2. Run scripts/deploy.sh:
                │     a. Find EC2 instance via SSM tag (ASG group name)
                │     b. Fetch DB credentials + JWT secret from Secrets Manager
                │     c. Generate SSM Run Command JSON on the runner
                │     d. Send command to EC2 via SSM Run Command
                │     e. EC2 pulls images from ECR, stops old containers,
                │        starts new ones with --network host
                │     f. Health checks: 5 retries per service on ports 3000-3003
                │     g. Poll SSM command status (up to 15 min)
                │  3. Print deployment output (success or failure)
                │
                ▼
        Result: containers running on EC2, or pipeline fails
```

| Step | Trigger | Tools | Destination | Outcome |
|---|---|---|---|---|
| Build | Push to `feature/docker-cicd-1` | Docker, GitHub Actions runner | Local image on runner | 4 images built in parallel |
| Scan | After build | Trivy (CRITICAL, HIGH) | Console output | Findings reported but **do not fail** the build (`exit-code: 0`) |
| Push | After scan | Amazon ECR login | ECR repos in `ap-south-2` | Images tagged with commit SHA |
| Deploy | After all 4 pushes succeed | AWS SSM Run Command, Secrets Manager | EC2 instance in sandbox VPC | Containers started with health checks |

**Honest limitations of this pipeline:**

- Trivy reports vulnerabilities but does not gate the build. A critical finding will not stop the pipeline.
- There is no manual approval gate between image push and deploy.
- AWS authentication uses long-lived IAM keys stored as GitHub secrets, not OIDC.
- There are no automated tests. The pipeline builds, scans, pushes, and deploys but never runs a test suite.
- The workflow only runs on `feature/docker-cicd-1`. It is not wired to `main` or to pull requests.
- Deployment targets a single sandbox EC2 instance, not a scaled or multi-AZ fleet.

## Security notes

- `docker-compose.yml` contains demo-only local credentials. Do not reuse them.
- Production database credentials and JWT secrets are stored in AWS Secrets Manager, not in the repository.
- The services set `rejectUnauthorized: false` for database TLS when connecting to a non-local host. This disables certificate verification and should not be used in production.
- The EC2 security group allows SSH from a single IP. Review this before any shared use.
- The deploy script fetches secrets on the GitHub Actions runner, writes them to a temporary SSM payload file (`/tmp/ssm-deploy.json`), and sends it to EC2 via SSM Run Command. The file is deleted after the command is sent. Ideally the EC2 instance should retrieve secrets through its own IAM role instead of the runner handling them.

## Completed and in progress

**Completed:**

- Microservices application: user-service, restaurant-service, order-service, frontend
- Docker Compose local development environment with PostgreSQL 15
- Dockerfiles for all services (multi-stage build for frontend)
- GitHub Actions pipeline: parallel build of 4 images, push to ECR, SSM-based deploy
- Trivy vulnerability scanning integrated into the pipeline (informational)
- SSM Run Command deployment with health checks and retry logic
- AWS infrastructure provisioned with Terraform (separate repository)
- Read-only infrastructure audit comparing source, state, and AWS

**In progress / incomplete:**

- Trivy scans do not block builds (`exit-code: 0`) — security findings are reported but not enforced
- No automated test suite exists or runs in the pipeline
- No manual approval gate between image push and deployment
- AWS authentication uses IAM keys, not OIDC
- Database TLS certificate verification is disabled in production (`rejectUnauthorized: false`)
- ALB uses HTTP only — no HTTPS listener or certificate
- Pipeline triggers only on `feature/docker-cicd-1`, not on `main` or pull requests
- Deployment targets a single sandbox EC2 instance, not a scaled fleet
- Both recent pipeline runs (commits `b855e73` and `56d933a`) failed at the deploy stage; the latest failed faster, suggesting the EC2 instance may need manual recovery
- The order-service status endpoint enforces forward-only transitions but does not restrict who may advance the status — any authenticated user can advance their own order to `delivered`. Role-based authorization is needed before production use
- No Terraform modules — both roots use direct resource declarations
- No Terraform modules — both roots use direct resource declarations

## Related project

The separate [`fooddash-infra`](https://github.com/sankalpmax/fooddash-infra) repository contains Terraform examples for AWS infrastructure. Its directory and branch names are not a claim that the system is production-ready.
