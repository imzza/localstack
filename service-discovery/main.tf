module "vpc" {
  # source = "./vpc.tf"
  source = "./modules/vpc"
  region = "us-east-1"
}

resource "aws_ecs_cluster" "service_discovery_ecs_cluster" {
  name = "service-discovery"
}

resource "aws_service_discovery_private_dns_namespace" "service_discovery_namespace" {
  name        = "imzza.net"
  description = "Namespace for Service Discovery"
  vpc         = module.vpc.vpc_id
}

resource "aws_service_discovery_service" "backend" {
  name = "backend-service"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.service_discovery_namespace.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 5
  }
}

resource "aws_service_discovery_service" "frontend" {
  name = "frontend-service"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.service_discovery_namespace.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 5
  }
}

resource "aws_ecs_task_definition" "frontend_task" {
  family = "frontend"
  container_definitions = jsonencode([{
    name      = "frontend",
    image     = "localhost.localstack.cloud:4510/imzza/frontend",
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
      { name = "BACKEND_SERVICE", value = "frontend-service.imzza.net" }, #backend.yelb-cftc  -full dns
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
    image     = "localhost.localstack.cloud:4510/imzza/backend",
    essential = true,
    memory    = 512,
    cpu       = 256,
    portMappings = [{
      containerPort = 3000,
      hostPort      = 3000,
      name          = "backend",
      protocol      = "tcp",
      appProtocol   = "http"
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

resource "aws_ecs_service" "frontend_service" {
  name            = "frontend"
  cluster         = aws_ecs_cluster.service_discovery_ecs_cluster.id
  task_definition = aws_ecs_task_definition.frontend_task.arn
  launch_type     = "FARGATE"
  desired_count   = 1

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
  service_registries {
    registry_arn = aws_service_discovery_service.frontend.arn
    port         = 5000
  }
}

resource "aws_ecs_service" "backend_service" {
  name            = "backend"
  cluster         = aws_ecs_cluster.service_discovery_ecs_cluster.id
  task_definition = aws_ecs_task_definition.backend_task.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets          = module.vpc.subnet_ids
    assign_public_ip = true
    security_groups  = [aws_security_group.service_security_group.id]
  }
  service_registries {
    registry_arn = aws_service_discovery_service.backend.arn
    port         = 3000
  }
}

output "load_balancer_url" {
  value = "http://${aws_alb.application_load_balancer.dns_name}:4566"
}