# Providing a reference to our default VPC
variable "region" {
  type    = string
  default = "us-east-1"
}

resource "aws_default_vpc" "default_vpc" {
  tags = {
    Name = "Default VPC"
  }
  enable_dns_support = true
  enable_dns_hostnames = true
}

resource "aws_default_subnet" "default_subnet_a" {
  availability_zone = "${var.region}a"
}

resource "aws_default_subnet" "default_subnet_b" {
  availability_zone = "${var.region}b"
}

resource "aws_default_subnet" "default_subnet_c" {
  availability_zone = "${var.region}c"
}

output "vpc_id" {
  value = aws_default_vpc.default_vpc.id
}

output "subnet_ids" {
  value = [
    "${aws_default_subnet.default_subnet_a.id}",
    "${aws_default_subnet.default_subnet_b.id}",
    "${aws_default_subnet.default_subnet_c.id}"
  ]
}