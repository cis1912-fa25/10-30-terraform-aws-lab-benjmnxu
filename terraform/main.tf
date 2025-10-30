terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# Get current AWS account ID
data "aws_caller_identity" "current" {}

# Create ECR repository for our Docker image
resource "aws_ecr_repository" "webapp" {
  name                 = "terraform-webapp-${var.pennkey}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "terraform-webapp-${var.pennkey}"
  }
}

# Output the ECR repository URL
output "ecr_repository_url" {
  description = "ECR repository URL for Docker images"
  value       = aws_ecr_repository.webapp.repository_url
}

resource "aws_security_group" "web_server" {
  name        = "terraform-web-server-sg-${var.pennkey}"
  description = "Security group for web server - allows SSH and HTTP"

  # Allow SSH from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH access"
  }

  # Allow HTTP from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP access"
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "terraform-web-server-sg-${var.pennkey}"
  }
}

resource "aws_key_pair" "deployer" {
  key_name   = "terraform-deployer-key-${var.pennkey}"
  public_key = file("~/.ssh/terraform-aws-key.pub")
}

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# IAM role for EC2 instances to pull from ECR
resource "aws_iam_role" "ec2_ecr_role" {
  name = "terraform-ec2-ecr-role-${var.pennkey}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "terraform-ec2-ecr-role-${var.pennkey}"
  }
}

# Attach policy to allow ECR access
resource "aws_iam_role_policy_attachment" "ecr_read_only" {
  role       = aws_iam_role.ec2_ecr_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Create instance profile
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "terraform-ec2-profile-${var.pennkey}"
  role = aws_iam_role.ec2_ecr_role.name
}

resource "aws_instance" "web_server" {
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = "t2.micro"
  key_name      = aws_key_pair.deployer.key_name

  vpc_security_group_ids = [aws_security_group.web_server.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  # Enable public IP
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/user_data.sh", {
    ecr_repo_url   = aws_ecr_repository.webapp.repository_url
    region         = "us-east-1"
    container_name = "webapp"
    host_port      = 80
    container_port = 80
    image_tag      = "latest"
  })

  user_data_replace_on_change = true

  tags = {
    Name = "terraform-web-server-${var.pennkey}"
  }

  # Ensure ECR repository exists first
  depends_on = [aws_ecr_repository.webapp]
}

output "instance_public_ip" {
  description = "Public IP address of the web server"
  value       = aws_instance.web_server.public_ip
}

output "instance_url" {
  description = "URL to access the web server"
  value       = "http://${aws_instance.web_server.public_ip}"
}