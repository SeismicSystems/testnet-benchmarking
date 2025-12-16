# Module expects AWS provider to be passed in
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Find latest Amazon Linux 2 AMI for x86_64
data "aws_ami" "amazon_linux" {
  count       = var.os_type == "amazon-linux" ? 1 : 0
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# Find latest Ubuntu 24.04 LTS AMI for x86_64
data "aws_ami" "ubuntu" {
  count       = var.os_type == "ubuntu" ? 1 : 0
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Create key pair
resource "aws_key_pair" "deployer" {
  key_name   = "deployer-key-${terraform.workspace}-${var.region}"
  public_key = file(var.ssh_public_key_path)
}

# Create security group for SSH
resource "aws_security_group" "ssh" {
  name        = "ssh-sg-${terraform.workspace}-${var.region}"
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

  tags = {
    Name   = "ssh-sg-${terraform.workspace}-${var.region}"
    Region = var.region
    Workspace = terraform.workspace
  }
}

# Create security group for Docker applications
resource "aws_security_group" "docker" {
  name        = "docker-sg-${terraform.workspace}-${var.region}"
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

  #ingress {
  #  from_port   = 30303
  #  to_port     = 30303
  #  protocol    = "tcp"
  #  cidr_blocks = ["0.0.0.0/0"]
  #}

  ingress {
    from_port   = 30303
    to_port     = 30303
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 9092
    to_port     = 9092
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
    Name   = "docker-sg-${terraform.workspace}-${var.region}"
    Region = var.region
    Workspace = terraform.workspace
  }
}

# Create instances
resource "aws_instance" "multi" {
  count = var.instances_per_region

  ami             = var.ami_id != "" ? var.ami_id : (var.os_type == "amazon-linux" ? data.aws_ami.amazon_linux[0].id : data.aws_ami.ubuntu[0].id)
  instance_type   = var.instance_type
  key_name        = aws_key_pair.deployer.key_name
  security_groups = [aws_security_group.ssh.name, aws_security_group.docker.name]

  user_data = base64encode(<<-EOF
#!/bin/bash

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
fi

# Create ubuntu user if it doesn't exist (for Amazon Linux)
if [[ "$OS" == "amzn" ]] && ! id "ubuntu" &>/dev/null; then
    useradd -m -s /bin/bash ubuntu
    usermod -aG wheel ubuntu
    echo "ubuntu ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
fi

# Update system packages and install Docker based on OS
if [[ "$OS" == "amzn" ]]; then
    # Amazon Linux
    yum update -y
    yum install -y docker
    systemctl start docker
    systemctl enable docker
    
    # Install Python 3.8 using Amazon Linux Extras
    yum install -y amazon-linux-extras
    amazon-linux-extras install python3.8 -y
elif [[ "$OS" == "ubuntu" ]]; then
    # Ubuntu
    apt-get update -y
    apt-get install -y docker.io
    systemctl start docker
    systemctl enable docker
    
    # Install Python 3
    apt-get install -y python3 python3-pip
fi

# Add ubuntu to docker group
usermod -a -G docker ubuntu

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Create symlink for docker-compose
ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

# Setup SSH access for ubuntu user
mkdir -p /home/ubuntu/.ssh
chmod 700 /home/ubuntu/.ssh

# Wait for ec2-user SSH keys to be set up and copy them
if [[ "$OS" == "amzn" ]]; then
    # Wait up to 30 seconds for ec2-user SSH keys
    for i in {1..30}; do
        if [ -f /home/ec2-user/.ssh/authorized_keys ]; then
            cp /home/ec2-user/.ssh/authorized_keys /home/ubuntu/.ssh/authorized_keys
            break
        fi
        sleep 1
    done
    
    # If still no keys, try to get them from instance metadata
    if [ ! -f /home/ubuntu/.ssh/authorized_keys ]; then
        curl -s http://169.254.169.254/latest/meta-data/public-keys/0/openssh-key > /home/ubuntu/.ssh/authorized_keys
    fi
fi

# Add additional public key if provided
%{if var.additional_ssh_public_key_path != ""}
echo "${file(var.additional_ssh_public_key_path)}" >> /home/ubuntu/.ssh/authorized_keys
%{endif}

chmod 600 /home/ubuntu/.ssh/authorized_keys 2>/dev/null
chown -R ubuntu:ubuntu /home/ubuntu/.ssh

# Verify Docker installation
docker --version
docker-compose --version

# Show Docker service status
systemctl status docker --no-pager

echo "Docker installation completed successfully!"
echo "Region: ${var.region}"
echo "Instance: $(hostname)"
echo "Ubuntu user setup completed"
EOF
  )

  root_block_device {
    volume_size           = var.volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name   = "instance-${terraform.workspace}-${var.region}-${count.index}"
    Region = var.region
    Index  = count.index
    Workspace = terraform.workspace
  }
}
