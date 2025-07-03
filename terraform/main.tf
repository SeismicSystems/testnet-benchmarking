terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Default provider
provider "aws" {
  region = "us-west-2"
}

# Provider for us-east-1
provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"
}

# Provider for eu-central-1
provider "aws" {
  alias  = "eu-central-1"
  region = "eu-central-1"
}

# Find latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# Create key pair
resource "aws_key_pair" "deployer" {
  key_name   = "deployer-key"
  public_key = file("~/.ssh/id_ed25519.pub")
}

# Create security group
resource "aws_security_group" "ssh" {
  name        = "ssh-sg"
  description = "Allow SSH access"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create instances
resource "aws_instance" "multi" {
  count = var.instances_per_region

  ami             = data.aws_ami.amazon_linux.id
  instance_type   = "m8g.xlarge"
  key_name        = aws_key_pair.deployer.key_name
  security_groups = [aws_security_group.ssh.name]

  # Copy SSH key to instance
  user_data = base64encode(<<-EOF
              #!/bin/bash
              mkdir -p /home/ec2-user/.ssh
              echo "$(cat ~/.ssh/id_ed25519.pub)" >> /home/ec2-user/.ssh/authorized_keys
              chmod 700 /home/ec2-user/.ssh
              chmod 600 /home/ec2-user/.ssh/authorized_keys
              chown -R ec2-user:ec2-user /home/ec2-user/.ssh
              EOF
  )

  tags = {
    Name = "instance-${count.index}"
  }
} 