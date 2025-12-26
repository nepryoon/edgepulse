# ECR for ML job images
resource "aws_ecr_repository" "ml" {
  name = "${var.project_name}-ml"
}

# Use default VPC/subnets for a minimal skeleton.
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_db_subnet_group" "default" {
  name       = "${var.project_name}-db-subnets"
  subnet_ids = data.aws_subnets.default.ids
}

resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "RDS security group"
  vpc_id      = data.aws_vpc.default.id

  # MVP: open to VPC only (adjust properly for production)
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "postgres" {
  identifier             = "${var.project_name}-pg"
  engine                 = "postgres"
  engine_version         = "16"
  instance_class         = var.db_instance_class
  allocated_storage      = 20
  db_name                = var.db_name
  username               = var.db_username
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.default.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  skip_final_snapshot    = true
}

resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"
}

# IAM role for ECS tasks
data "aws_iam_policy_document" "ecs_task_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task_execution" {
  name               = "${var.project_name}-ecs-task-exec"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_exec_attach" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Task definition (placeholder container image; update after pushing)
resource "aws_ecs_task_definition" "ml_score" {
  family                   = "${var.project_name}-ml-score"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([{
    name      = "ml-score"
    image     = "${aws_ecr_repository.ml.repository_url}:latest"
    essential = true
    environment = [
      { name = "DATABASE_URL", value = "postgresql://${var.db_username}:${var.db_password}@${aws_db_instance.postgres.address}:5432/${var.db_name}" },
      { name = "FEATURE_WINDOW_SEC", value = "300" },
      { name = "SCORE_INTERVAL_SEC", value = "600" }
    ],
    command = ["score", "--tenant", "REPLACE", "--metric", "REPLACE", "--since-hours", "24"]
  }])
}

# Scheduler role
data "aws_iam_policy_document" "events_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "scheduler" {
  name               = "${var.project_name}-scheduler-role"
  assume_role_policy = data.aws_iam_policy_document.events_assume.json
}

# Allow scheduler to run ECS task
data "aws_iam_policy_document" "scheduler_policy" {
  statement {
    actions = ["ecs:RunTask"]
    resources = [aws_ecs_task_definition.ml_score.arn]
  }
  statement {
    actions = ["iam:PassRole"]
    resources = [aws_iam_role.ecs_task_execution.arn]
  }
}

resource "aws_iam_role_policy" "scheduler_inline" {
  name   = "${var.project_name}-scheduler-inline"
  role   = aws_iam_role.scheduler.id
  policy = data.aws_iam_policy_document.scheduler_policy.json
}

# EventBridge Scheduler (cron) – adjust schedule to your needs
resource "aws_scheduler_schedule" "ml_score_hourly" {
  name       = "${var.project_name}-ml-score-hourly"
  group_name = "default"

  flexible_time_window { mode = "OFF" }

  schedule_expression = "rate(1 hour)"

  target {
    arn      = aws_ecs_cluster.main.arn
    role_arn = aws_iam_role.scheduler.arn

    ecs_parameters {
      task_definition_arn = aws_ecs_task_definition.ml_score.arn
      launch_type         = "FARGATE"
      network_configuration {
        subnets         = data.aws_subnets.default.ids
        assign_public_ip = true
      }
    }
  }
}
