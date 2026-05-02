# 🖥️ IT Operations Dashboard — 3-Tier Web App on AWS

![Terraform](https://img.shields.io/badge/Terraform-1.x-7B42BC?logo=terraform)
![AWS](https://img.shields.io/badge/AWS-EC2%20%7C%20RDS%20%7C%20ALB%20%7C%20VPC-FF9900?logo=amazonaws)
![Python](https://img.shields.io/badge/Python-3.12-3776AB?logo=python)
![Flask](https://img.shields.io/badge/Flask-3.0-000000?logo=flask)
![CI/CD](https://img.shields.io/badge/CI%2FCD-GitHub%20Actions-2088FF?logo=githubactions)
![License](https://img.shields.io/badge/License-MIT-green)

A production-grade 3-tier web application hosted on AWS — an IT Operations Dashboard that displays real-time service status and live incident data from the [Incident Log API](https://github.com/Drakeshh/aws-incident-api-terraform). Fully provisioned with Terraform and deployed via GitHub Actions.

**Live demo:** [https://project3.sergipratmerin.com](https://project3.sergipratmerin.com)

---

## 📐 Architecture

```
Internet
    │
    ▼
┌─────────────────────────────────────────┐
│           Public Subnets                │
│   CloudFront → Application Load Balancer│
└─────────────────┬───────────────────────┘
                  │
    ┌─────────────▼───────────────┐
    │       Private Subnets       │
    │   EC2 Auto Scaling Group    │
    │   (Flask + Gunicorn)        │
    └─────────────┬───────────────┘
                  │
    ┌─────────────▼───────────────┐
    │       Private Subnets       │
    │     RDS PostgreSQL          │
    └─────────────────────────────┘
         VPC (10.0.0.0/16)
```

### Services used

| Service | Tier | Purpose |
|---|---|---|
| **CloudFront** | Edge | CDN + HTTPS termination |
| **ACM** | Edge | SSL/TLS certificate |
| **Route 53** | DNS | Custom domain routing |
| **ALB** | Tier 1 | Load balancing across EC2 instances |
| **EC2 + Auto Scaling** | Tier 2 | Flask web application servers |
| **RDS PostgreSQL** | Tier 3 | Relational database for service status |
| **VPC** | Network | Isolated private network with public/private subnets |
| **IAM** | Security | Least-privilege roles for EC2 and SSM access |
| **GitHub Actions** | CI/CD | Auto-deploys on every push to `main` |
| **Terraform** | IaC | Provisions all AWS resources |

---

## 📁 Project structure

```
.
├── .github/
│   └── workflows/
│       └── deploy.yml           # GitHub Actions CI/CD pipeline
├── terraform/
│   ├── main.tf                  # VPC, EC2, RDS, ALB, CloudFront, Auto Scaling
│   ├── variables.tf             # Input variables
│   ├── outputs.tf               # ALB URL, CloudFront URL, RDS endpoint
│   └── providers.tf             # AWS provider + S3 backend
├── app/
│   ├── app.py                   # Flask dashboard application
│   └── requirements.txt         # Python dependencies
├── .gitignore
├── LICENSE
└── README.md
```

---

## 🌐 Dashboard features

- **Service status table** — displays operational status of internal services from RDS
- **Live incident feed** — pulls real-time data from the [Incident Log API](https://github.com/Drakeshh/aws-incident-api-terraform) (Project 2)
- **Stats overview** — open incidents, in-progress, resolved, services up
- **Color-coded severity** — critical, high, medium, low incident indicators
- **Auto-refreshing** — always shows current infrastructure state

---

## 🔒 Security architecture

```
Internet → CloudFront → ALB (public subnet)
                          │
                    EC2 (private subnet)  ← only accepts traffic from ALB
                          │
                    RDS (private subnet)  ← only accepts traffic from EC2
```

- **3-tier isolation** — each layer only communicates with the layer directly above/below it
- **Private subnets** — EC2 and RDS have no direct internet access
- **Security groups** — ALB accepts 80/443 from internet; EC2 only accepts 5000 from ALB; RDS only accepts 5432 from EC2
- **SSM Session Manager** — EC2 access without SSH keys or open ports
- **No hardcoded credentials** — database password stored in `terraform.tfvars` (gitignored) and GitHub Secrets

---

## 🚀 Getting started

### Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) v1.0+
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) configured
- An AWS account with appropriate permissions
- Python 3.12+

### 1. Clone the repository

```bash
git clone https://github.com/Drakeshh/aws-3tier-dashboard-terraform.git
cd aws-3tier-dashboard-terraform
```

### 2. Configure variables

Create `terraform/terraform.tfvars`:

```hcl
aws_region    = "eu-west-3"
environment   = "production"
project_name  = "dashboard"
db_password   = "YourStrongPassword123#"
```

### 3. Deploy infrastructure

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

### 4. Set up GitHub Actions secrets

In your GitHub repository go to **Settings → Secrets and variables → Actions** and add:

| Secret | Description |
|---|---|
| `AWS_ACCESS_KEY_ID` | IAM user access key |
| `AWS_SECRET_ACCESS_KEY` | IAM user secret key |

### 5. Push to deploy

```bash
git add .
git commit -m "feat: update dashboard"
git push origin main
```

---

## ⚙️ CI/CD pipeline

```
push to main
     │
     ├── 1. Checkout code
     ├── 2. Configure AWS credentials
     ├── 3. Setup Terraform
     ├── 4. terraform init
     ├── 5. terraform plan
     └── 6. terraform apply
```

---

## 💡 Key concepts demonstrated

- **3-tier architecture** — presentation, application and data layers properly separated
- **VPC design** — public and private subnets across 2 availability zones
- **Auto Scaling** — EC2 instances scale automatically based on health and load
- **Infrastructure as Code** — entire environment reproducible with one `terraform apply`
- **Cost management** — environment can be torn down with `terraform destroy` and rebuilt on demand
- **Least-privilege IAM** — EC2 instances only have SSM access, nothing else
- **Multi-project integration** — dashboard consumes live data from Project 2 API

---

## 💰 Cost management

This project uses services that incur costs outside the AWS free tier:

| Service | Approximate monthly cost |
|---|---|
| RDS `db.t3.micro` | ~$15/month |
| ALB | ~$20/month |
| EC2 `t3.micro` | ~$8/month |

**Recommended approach for portfolio use:**
```bash
# Shut down when not needed
terraform destroy

# Rebuild when needed
terraform apply
```

All infrastructure rebuilds identically in ~10 minutes.

---

## 🌱 Possible extensions

- Add **HTTPS on the ALB** with an internal ACM certificate
- Implement **RDS Multi-AZ** for high availability
- Add **CloudWatch alarms** for EC2 and RDS metrics
- Enable **Auto Scaling policies** based on CPU utilization
- Add **ElastiCache** as a caching layer between EC2 and RDS
- Implement **Blue/Green deployments** via CodeDeploy

---

## 📚 Resources

- [AWS VPC documentation](https://docs.aws.amazon.com/vpc/)
- [AWS EC2 Auto Scaling](https://docs.aws.amazon.com/autoscaling/)
- [AWS RDS documentation](https://docs.aws.amazon.com/rds/)
- [Terraform AWS Provider docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

---

## 📄 License

MIT — feel free to use this as a starting point for your own projects.

---
