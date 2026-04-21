# ─────────────────────────────────────────
# VPC & NETWORKING
# ─────────────────────────────────────────

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = var.environment
  }
}

# Public subnets (ALB lives here)
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index + 1}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.project_name}-public-${count.index + 1}"
    Environment = var.environment
  }
}

# Private subnets (EC2 and RDS live here)
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name        = "${var.project_name}-private-${count.index + 1}"
    Environment = var.environment
  }
}

# Internet Gateway (allows public subnets to reach internet)
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.project_name}-igw"
    Environment = var.environment
  }
}

# Route table for public subnets
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name        = "${var.project_name}-public-rt"
    Environment = var.environment
  }
}

# Associate public subnets with public route table
resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ─────────────────────────────────────────
# SECURITY GROUPS
# ─────────────────────────────────────────

# ALB security group - accepts HTTP/HTTPS from internet
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-alb-sg"
    Environment = var.environment
  }
}

# EC2 security group - only accepts traffic from ALB
resource "aws_security_group" "ec2" {
  name        = "${var.project_name}-ec2-sg"
  description = "Security group for EC2 instances"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-ec2-sg"
    Environment = var.environment
  }
}

# RDS security group - only accepts traffic from EC2
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "Security group for RDS instance"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  tags = {
    Name        = "${var.project_name}-rds-sg"
    Environment = var.environment
  }
}

# ─────────────────────────────────────────
# RDS POSTGRESQL
# ─────────────────────────────────────────

resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name        = "${var.project_name}-db-subnet-group"
    Environment = var.environment
  }
}

resource "aws_db_instance" "main" {
  identifier        = "${var.project_name}-db"
  engine            = "postgres"
  engine_version    = "17.4"
  instance_class    = "db.t3.micro"
  allocated_storage = 20

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  skip_final_snapshot = true
  publicly_accessible = false

  tags = {
    Name        = "${var.project_name}-db"
    Environment = var.environment
  }
}

# ─────────────────────────────────────────
# EC2 AUTO SCALING
# ─────────────────────────────────────────

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2.name
}

resource "aws_iam_role" "ec2" {
  name = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_launch_template" "app" {
  name_prefix   = "${var.project_name}-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2.name
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.ec2.id]
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    yum install -y python3 python3-pip git

    # Install Flask app dependencies
    pip3 install flask psycopg2-binary requests gunicorn

    # Create app directory
    mkdir -p /app

    # Create Flask app
    cat > /app/app.py << 'APPEOF'
    import os
    import json
    import requests
    from flask import Flask, render_template_string
    import psycopg2
    from datetime import datetime

    app = Flask(__name__)

    DB_HOST = "${aws_db_instance.main.address}"
    DB_NAME = "${var.db_name}"
    DB_USER = "${var.db_username}"
    DB_PASS = "${var.db_password}"
    INCIDENT_API = "https://api.project2.sergipratmerin.com/incidents"

    def get_db():
        return psycopg2.connect(
            host=DB_HOST, database=DB_NAME,
            user=DB_USER, password=DB_PASS
        )

    def init_db():
        conn = get_db()
        cur = conn.cursor()
        cur.execute("""
            CREATE TABLE IF NOT EXISTS services (
                id SERIAL PRIMARY KEY,
                name VARCHAR(100) NOT NULL,
                status VARCHAR(20) DEFAULT 'operational',
                last_checked TIMESTAMP DEFAULT NOW()
            )
        """)
        cur.execute("SELECT COUNT(*) FROM services")
        if cur.fetchone()[0] == 0:
            services = [
                ('Web Server', 'operational'),
                ('Database', 'operational'),
                ('API Gateway', 'operational'),
                ('Cache Server', 'degraded'),
                ('Email Service', 'operational'),
                ('Backup Service', 'operational'),
            ]
            cur.executemany(
                "INSERT INTO services (name, status) VALUES (%s, %s)",
                services
            )
        conn.commit()
        cur.close()
        conn.close()

    DASHBOARD_HTML = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>IT Operations Dashboard</title>
        <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
        <style>
            body { background: #0f1923; color: #fff; font-family: 'Segoe UI', sans-serif; }
            .navbar { background: #1a2634 !important; border-bottom: 1px solid #2d3f50; }
            .card { background: #1a2634; border: 1px solid #2d3f50; }
            .card-header { background: #243447; border-bottom: 1px solid #2d3f50; }
            .badge-operational { background: #1a6b3c; color: #4ade80; }
            .badge-degraded { background: #7c5a00; color: #fbbf24; }
            .badge-down { background: #7f1d1d; color: #f87171; }
            .stat-card { border-left: 4px solid; }
            .stat-critical { border-color: #ef4444; }
            .stat-warning { border-color: #f59e0b; }
            .stat-success { border-color: #22c55e; }
            .stat-info { border-color: #3b82f6; }
            .incident-critical { border-left: 3px solid #ef4444; }
            .incident-high { border-left: 3px solid #f59e0b; }
            .incident-medium { border-left: 3px solid #3b82f6; }
            .incident-low { border-left: 3px solid #22c55e; }
        </style>
    </head>
    <body>
    <nav class="navbar navbar-dark mb-4">
        <div class="container">
            <span class="navbar-brand fw-bold">IT Operations Dashboard</span>
            <span class="text-muted small">{{ current_time }}</span>
        </div>
    </nav>
    <div class="container">
        <div class="row g-3 mb-4">
            <div class="col-md-3">
                <div class="card stat-card stat-critical p-3">
                    <div class="text-muted small">Open Incidents</div>
                    <div class="fs-2 fw-bold text-danger">{{ stats.open }}</div>
                </div>
            </div>
            <div class="col-md-3">
                <div class="card stat-card stat-warning p-3">
                    <div class="text-muted small">In Progress</div>
                    <div class="fs-2 fw-bold text-warning">{{ stats.in_progress }}</div>
                </div>
            </div>
            <div class="col-md-3">
                <div class="card stat-card stat-success p-3">
                    <div class="text-muted small">Resolved</div>
                    <div class="fs-2 fw-bold text-success">{{ stats.resolved }}</div>
                </div>
            </div>
            <div class="col-md-3">
                <div class="card stat-card stat-info p-3">
                    <div class="text-muted small">Services Up</div>
                    <div class="fs-2 fw-bold text-info">{{ stats.services_up }}/{{ stats.total_services }}</div>
                </div>
            </div>
        </div>
        <div class="row g-3">
            <div class="col-md-6">
                <div class="card">
                    <div class="card-header fw-bold">Service Status</div>
                    <div class="card-body p-0">
                        <table class="table table-dark table-hover mb-0">
                            <thead><tr><th>Service</th><th>Status</th></tr></thead>
                            <tbody>
                            {% for s in services %}
                            <tr>
                                <td>{{ s.name }}</td>
                                <td><span class="badge badge-{{ s.status }}">{{ s.status }}</span></td>
                            </tr>
                            {% endfor %}
                            </tbody>
                        </table>
                    </div>
                </div>
            </div>
            <div class="col-md-6">
                <div class="card">
                    <div class="card-header fw-bold">Recent Incidents</div>
                    <div class="card-body p-0">
                        {% for i in incidents %}
                        <div class="p-3 border-bottom border-secondary incident-{{ i.severity }}">
                            <div class="d-flex justify-content-between">
                                <strong class="small">{{ i.title }}</strong>
                                <span class="badge bg-secondary">{{ i.severity }}</span>
                            </div>
                            <div class="text-muted small mt-1">{{ i.status }} · {{ i.created_at[:10] }}</div>
                        </div>
                        {% endfor %}
                    </div>
                </div>
            </div>
        </div>
        <div class="text-center text-muted small mt-4 pb-3">
            Built with AWS EC2 · RDS · ALB · Auto Scaling · Terraform
            · <a href="https://github.com/Drakeshh/aws-3tier-dashboard-terraform" class="text-muted">GitHub</a>
        </div>
    </div>
    </body>
    </html>
    """

    @app.route('/')
    def dashboard():
        try:
            conn = get_db()
            cur = conn.cursor()
            cur.execute("SELECT name, status FROM services ORDER BY name")
            rows = cur.fetchall()
            services = [{'name': r[0], 'status': r[1]} for r in rows]
            cur.close()
            conn.close()
        except:
            services = []

        try:
            resp = requests.get(INCIDENT_API, timeout=5)
            incidents = resp.json().get('incidents', [])[:5]
        except:
            incidents = []

        open_inc = sum(1 for i in incidents if i.get('status') == 'open')
        in_prog  = sum(1 for i in incidents if i.get('status') == 'in-progress')
        resolved = sum(1 for i in incidents if i.get('status') == 'resolved')
        svc_up   = sum(1 for s in services if s['status'] == 'operational')

        stats = {
            'open': open_inc,
            'in_progress': in_prog,
            'resolved': resolved,
            'services_up': svc_up,
            'total_services': len(services)
        }

        return render_template_string(
            DASHBOARD_HTML,
            services=services,
            incidents=incidents,
            stats=stats,
            current_time=datetime.utcnow().strftime('%Y-%m-%d %H:%M UTC')
        )

    if __name__ == '__main__':
        init_db()
        app.run(host='0.0.0.0', port=5000)
    APPEOF

    # Initialize DB and start app
    cd /app
    python3 -c "
    import sys
    sys.path.insert(0, '/app')
    from app import init_db
    init_db()
    "

    # Start with gunicorn
    gunicorn --bind 0.0.0.0:5000 --workers 2 --daemon app:app

    EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.project_name}-ec2"
      Environment = var.environment
    }
  }
}

resource "aws_autoscaling_group" "app" {
  name                = "${var.project_name}-asg"
  vpc_zone_identifier = aws_subnet.private[*].id
  target_group_arns   = [aws_lb_target_group.app.arn]
  health_check_type   = "ELB"
  min_size            = 1
  max_size            = 3
  desired_capacity    = 1

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-ec2"
    propagate_at_launch = true
  }
}

# ─────────────────────────────────────────
# APPLICATION LOAD BALANCER
# ─────────────────────────────────────────

resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name        = "${var.project_name}-alb"
    Environment = var.environment
  }
}

resource "aws_lb_target_group" "app" {
  name     = "${var.project_name}-tg"
  port     = 5000
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# ─────────────────────────────────────────
# ACM CERTIFICATE (us-east-1 for CloudFront)
# ─────────────────────────────────────────

resource "aws_acm_certificate" "website" {
  provider          = aws.us_east_1
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Environment = var.environment
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.website.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = "Z0947520WDN1EWGENS8T"
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "website" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.website.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# ─────────────────────────────────────────
# CLOUDFRONT
# ─────────────────────────────────────────

resource "aws_cloudfront_distribution" "website" {
  enabled = true
  aliases = [var.domain_name]

  origin {
    domain_name = aws_lb.main.dns_name
    origin_id   = "ALBOrigin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "ALBOrigin"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = true
      cookies {
        forward = "all"
      }
    }

    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.website.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = {
    Environment = var.environment
  }
}

# ─────────────────────────────────────────
# ROUTE 53
# ─────────────────────────────────────────

resource "aws_route53_record" "website" {
  zone_id = "Z0947520WDN1EWGENS8T"
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.website.domain_name
    zone_id                = aws_cloudfront_distribution.website.hosted_zone_id
    evaluate_target_health = false
  }
}