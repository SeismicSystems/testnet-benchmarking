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

# Find latest Amazon Linux 2 AMI for x86_64
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

# Create security group for SSH
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

# Create security group for Docker applications
resource "aws_security_group" "docker" {
  name        = "docker-sg"
  description = "Allow Docker application access"

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

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8545
    to_port     = 8545
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8546
    to_port     = 8546
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8551
    to_port     = 8551
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 9001
    to_port     = 9001
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 30303
    to_port     = 30303
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 30303
    to_port     = 30303
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8551
    to_port     = 8551
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 9090
    to_port     = 9090
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
  instance_type   = "m5.xlarge"  # x86_64 instance type (16GB RAM, 4 vCPUs)
  key_name        = aws_key_pair.deployer.key_name
  security_groups = [aws_security_group.ssh.name, aws_security_group.docker.name]

  # Copy SSH key to instance and install Docker
  user_data = base64encode(<<-EOF
              #!/bin/bash
              
              # Update system packages
              yum update -y
              
              # Install Docker
              yum install -y docker
              
              # Start and enable Docker service
              systemctl start docker
              systemctl enable docker
              
              # Add ec2-user to docker group
              usermod -a -G docker ec2-user
              
              # Install Docker Compose
              curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
              chmod +x /usr/local/bin/docker-compose
              
              # Create symlink for docker-compose
              ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
              
              # Setup SSH access
              mkdir -p /home/ec2-user/.ssh
              echo "$(cat ~/.ssh/id_ed25519.pub)" >> /home/ec2-user/.ssh/authorized_keys
              chmod 700 /home/ec2-user/.ssh
              chmod 600 /home/ec2-user/.ssh/authorized_keys
              chown -R ec2-user:ec2-user /home/ec2-user/.ssh
              
              # Create application directory
              #mkdir -p /home/ec2-user/app
              #chown ec2-user:ec2-user /home/ec2-user/app
              
              # Verify Docker installation
              docker --version
              docker-compose --version
              
              # Show Docker service status
              systemctl status docker --no-pager
              
              echo "Docker installation completed successfully!"
              EOF
  )

  root_block_device {
    volume_size = 200  # 200GB root volume (default is 8GB)
    volume_type = "gp3"
    encrypted   = true
    delete_on_termination = true
  }

  tags = {
    Name = "instance-${count.index}"
  }
} 
