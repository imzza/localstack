module "vpc" {
  source = "./modules/vpc"
  region = "us-east-1"
}

resource "aws_service_discovery_http_namespace" "service_connect_namespace" {
  name        = "yelb-cftc"
  description = "Namespace for Service Discovery"
}

resource "aws_ecs_cluster" "ecs_cluster" {
  name = "service-connect-dev"
  service_connect_defaults {
    namespace = aws_service_discovery_http_namespace.service_connect_namespace.arn
  }
}


resource "aws_ecs_task_definition" "frontend_task" {
  family = "frontend"
  container_definitions = jsonencode([{
    name      = "frontend",
    image     = "imzza/frontend:latest",
    essential = true,
    memory    = 512,
    cpu       = 256,
    portMappings = [{
      containerPort = 5000,
      hostPort      = 5000,
      name          = "frontend",
      protocol      = "tcp",
      appProtocol   = "http"
    }],
    environment = [
      { name = "PORT", value = "5000" },
      { name = "BACKEND_SERVICE", value = "backend.yelb-cftc" }, #backend.yelb-cftc  -full dns
      { name = "BACKEND_SERVICE_PORT", value = "3000" },
    ],
  }])
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  memory                   = 512
  cpu                      = 256
  execution_role_arn       = aws_iam_role.ecsTaskExecutionRole.arn
}


resource "aws_ecs_task_definition" "backend_task" {
  family = "backend"
  container_definitions = jsonencode([{
    name      = "backend",
    image     = "imzza/backend:latest",
    essential = true,
    memory    = 512,
    cpu       = 256,
    portMappings = [{
      containerPort = 3000,
      hostPort      = 3000,
      name          = "backend",
      protocol      = "tcp",
      appProtocol   = "http" #skip this for services like database or redis or grpc services
    }],
    environment = [
      { name = "PORT", value = "3000" },
    ],
  }])
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  memory                   = 512
  cpu                      = 256
  execution_role_arn       = aws_iam_role.ecsTaskExecutionRole.arn
}


resource "aws_alb" "application_load_balancer" {
  name               = "service-connect"
  load_balancer_type = "application"
  subnets            = module.vpc.subnet_ids
  security_groups    = ["${aws_security_group.load_balancer_security_group.id}"]
}

resource "aws_security_group" "load_balancer_security_group" {
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Allowing traffic in from all sources
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb_target_group" "target_group" {
  name        = "target-group"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_alb.application_load_balancer.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.target_group.arn
  }
}

resource "aws_ecs_service" "frontend_service" {
  name             = "frontend"
  cluster          = aws_ecs_cluster.ecs_cluster.id
  task_definition  = aws_ecs_task_definition.frontend_task.arn
  launch_type      = "FARGATE"
  platform_version = "LATEST"
  deployment_controller {
    type = "ECS"
  }
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100
  enable_ecs_managed_tags            = true
  enable_execute_command             = true

  desired_count = 1

  load_balancer {
    target_group_arn = aws_lb_target_group.target_group.arn
    container_name   = aws_ecs_task_definition.frontend_task.family
    container_port   = 5000
  }

  network_configuration {
    subnets          = module.vpc.subnet_ids
    assign_public_ip = true
    security_groups  = [aws_security_group.service_security_group.id]
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.service_connect_namespace.arn
    service {
      port_name      = "frontend"
      discovery_name = "frontend"
      client_alias {
        dns_name = "frontend.yelb-cftc"
        port     = 5000
      }
    }
  }
}

resource "aws_ecs_service" "backend_service" {
  name            = "backend"
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.backend_task.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  platform_version = "LATEST"
  deployment_controller {
    type = "ECS"
  }
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100
  enable_ecs_managed_tags            = true
  enable_execute_command             = true

  network_configuration {
    subnets          = module.vpc.subnet_ids
    assign_public_ip = true
    security_groups  = [aws_security_group.service_security_group.id]
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.service_connect_namespace.arn
    service {
      discovery_name = "backend"
      port_name      = "backend"
      client_alias {
        dns_name = "backend.yelb-cftc"
        port     = 3000
      }
    }
  }
}

resource "aws_security_group" "service_security_group" {
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    # Only allowing traffic in from the load balancer security group
    security_groups = ["${aws_security_group.load_balancer_security_group.id}"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

output "load_balancer_url" {
  value = "http://${aws_alb.application_load_balancer.dns_name}:4566"
}