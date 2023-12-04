provider "aws" {
  region = "us-east-1"  # Change this to your desired AWS region
}

# Create an IAM role for EKS cluster
resource "aws_iam_role" "eks_cluster" {
  name = "eks_cluster"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })
}

# Attach the AmazonEKSClusterPolicy policy
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

# Create an IAM role for EKS worker nodes
resource "aws_iam_role" "eks_node_group" {
  name = "eks_node_group"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

# Attach the AmazonEKSWorkerNodePolicy and AmazonEC2ContainerRegistryReadOnly policies
resource "aws_iam_role_policy_attachment" "eks_node_group_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_group.name
}

resource "aws_iam_role_policy_attachment" "eks_node_group_ecr_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_group.name
}

# Create a custom VPC
resource "aws_vpc" "custom_vpc" {
  cidr_block = "10.0.0.0/16"  # Replace with your desired CIDR block
  enable_dns_support = true
  enable_dns_hostnames = true

  tags = {
    Name = "my-custom-vpc"
  }
}

# Create public subnets within the VPC
resource "aws_subnet" "public_subnet_a" {
  vpc_id                  = aws_vpc.custom_vpc.id
  cidr_block              = "10.0.1.0/24"  # Replace with your desired CIDR block
  availability_zone       = "us-east-1a"  # Replace with your desired availability zone
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-a"
  }
}

resource "aws_subnet" "public_subnet_b" {
  vpc_id                  = aws_vpc.custom_vpc.id
  cidr_block              = "10.0.2.0/24"  # Replace with your desired CIDR block
  availability_zone       = "us-east-1b"  # Replace with your desired availability zone
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-b"
  }
}

# Create private subnets within the VPC
resource "aws_subnet" "private_subnet_a" {
  vpc_id                  = aws_vpc.custom_vpc.id
  cidr_block              = "10.0.3.0/24"  # Replace with your desired CIDR block
  availability_zone       = "us-east-1a"  # Replace with your desired availability zone

  tags = {
    Name = "private-subnet-a"
  }
}

resource "aws_subnet" "private_subnet_b" {
  vpc_id                  = aws_vpc.custom_vpc.id
  cidr_block              = "10.0.4.0/24"  # Replace with your desired CIDR block
  availability_zone       = "us-east-1b"  # Replace with your desired availability zone

  tags = {
    Name = "private-subnet-b"
  }
}

# Create an Internet Gateway (IGW)
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.custom_vpc.id

  tags = {
    Name = "my-igw"
  }
}

# Create a route table for public subnets and associate it with the IGW
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.custom_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public-route-table"
  }
}

# Associate public subnets with the public route table
resource "aws_route_table_association" "public_subnet_association_a" {
  subnet_id      = aws_subnet.public_subnet_a.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "public_subnet_association_b" {
  subnet_id      = aws_subnet.public_subnet_b.id
  route_table_id = aws_route_table.public_route_table.id
}

# Create a NAT Gateway for each private subnet
resource "aws_nat_gateway" "nat_gateway_a" {
  allocation_id = aws_subnet.public_subnet_a.id
  subnet_id     = aws_subnet.private_subnet_a.id

  tags = {
    Name = "nat-gateway-a"
  }
}

resource "aws_nat_gateway" "nat_gateway_b" {
  allocation_id = aws_subnet.public_subnet_b.id
  subnet_id     = aws_subnet.private_subnet_b.id

  tags = {
    Name = "nat-gateway-b"
  }
}

# Create a route table for private subnets and associate it with the NAT Gateways
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.custom_vpc.id

  tags = {
    Name = "private-route-table"
  }
}

# Add a default route to the NAT Gateway for each private subnet
resource "aws_route" "private_subnet_route_a" {
  route_table_id         = aws_route_table.private_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway_a.id
}

resource "aws_route" "private_subnet_route_b" {
  route_table_id         = aws_route_table.private_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway_b.id
}

# Define the AWS EKS cluster
module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  cluster_name    = "my-eks-cluster"
  subnets         = [
    aws_subnet.public_subnet_a.id,
    aws_subnet.public_subnet_b.id,
    aws_subnet.private_subnet_a.id,
    aws_subnet.private_subnet_b.id,
  ]
  vpc_id          = aws_vpc.custom_vpc.id
  cluster_version = "1.28"

  node_groups = {
    eks_nodes = {
      desired_capacity = 2
      max_capacity     = 4
      min_capacity     = 2

      key_name = "dec4.pem"  # Replace with your key pair name

      instance_type = "t2.small"  # Replace with your desired EC2 instance type

      additional_security_group_ids = []  # Add additional security groups if needed

      iam_instance_profile = aws_iam_instance_profile.eks_node_profile.name

      tags = {
        Terraform   = "true"
        Environment = "dev"
      }
    }
  }
}

# Create an IAM instance profile for the EKS worker nodes
resource "aws_iam_instance_profile" "eks_node_profile" {
  name = "eks_node_profile"

  roles = [aws_iam_role.eks_node_group.name]
}

# Create a security group for EKS worker nodes allowing all traffic
resource "aws_security_group" "eks_worker_sg" {
  name        = "eks_worker_sg"
  description = "Security group for EKS worker nodes"
  vpc_id      = aws_vpc.custom_vpc.id

  // Allow all inbound traffic
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }

  // Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }
}

output "kubeconfig" {
  value = module.eks.kubeconfig
}
