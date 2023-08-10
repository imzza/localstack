# resource "aws_ecr_repository" "backend" {
#   name = "backend"
# }

# resource "aws_ecr_repository" "frontend" {
#   name = "frontend"
# }

# output "ecr_repo_urls" {
#   value = {
#     backend  = aws_ecr_repository.backend.repository_url
#     frontend = aws_ecr_repository.frontend.repository_url
#   }
# }

# localhost.localstack.cloud:4510/frontend
# localhost.localstack.cloud:4510/backend