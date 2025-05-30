# 🏗️ Terraform 설정 가이드 (Infrastructure as Code)

> **⏱️ 예상 소요시간**: 약 90-120분  
> **💡 난이도**: 중급  
> **📋 목표**: Terraform을 사용하여 AWS 인프라를 코드로 정의하고 관리합니다.

---

## 📁 프로젝트 디렉토리 구조

```
terraform/
├── backend/                    # S3 + DynamoDB 백엔드
├── modules/                    # 재사용 가능한 모듈들
│   ├── vpc/
│   ├── security-groups/
│   ├── eks/
│   └── iam/
├── environments/               # 환경별 설정
│   ├── dev/
│   └── prod/
└── scripts/                   # 배포 스크립트
```

---

## 🚀 1단계: 백엔드 설정

### 프로젝트 초기화
```bash
mkdir -p terraform/{backend,modules/{vpc,security-groups,eks,iam},environments/{dev,prod},scripts}
cd terraform
```

### backend/main.tf
```hcl
terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-2"
  default_tags {
    tags = {
      Project   = "openwebui"
      ManagedBy = "terraform"
    }
  }
}

# S3 버킷 (Terraform 상태 저장)
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "terraform_state" {
  bucket = "openwebui-terraform-state-${random_id.bucket_suffix.hex}"
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# DynamoDB 테이블 (Terraform 락)
resource "aws_dynamodb_table" "terraform_lock" {
  name         = "openwebui-terraform-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}
```

### 백엔드 배포
```bash
cd backend
terraform init
terraform apply
terraform output  # 출력값 확인
```

---

## 🌐 2단계: VPC 모듈

### modules/vpc/main.tf
```hcl
data "aws_availability_zones" "available" {
  state = "available"
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-vpc"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  })
}

# 인터넷 게이트웨이
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = merge(var.tags, { Name = "${var.name_prefix}-igw" })
}

# 퍼블릭 서브넷
resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-public-subnet-${count.index + 1}"
    "kubernetes.io/role/elb" = "1"
  })
}

# 프라이빗 서브넷
resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-private-subnet-${count.index + 1}"
    "kubernetes.io/role/internal-elb" = "1"
  })
}

# NAT Gateway
resource "aws_eip" "nat" {
  count  = var.enable_nat_gateway ? length(var.public_subnet_cidrs) : 0
  domain = "vpc"
}

resource "aws_nat_gateway" "main" {
  count = var.enable_nat_gateway ? length(var.public_subnet_cidrs) : 0

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
}

# 라우트 테이블
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_route_table" "private" {
  count  = length(var.private_subnet_cidrs)
  vpc_id = aws_vpc.main.id

  dynamic "route" {
    for_each = var.enable_nat_gateway ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.main[count.index].id
    }
  }
}

# 라우트 테이블 연결
resource "aws_route_table_association" "public" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = length(var.private_subnet_cidrs)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}
```

### modules/vpc/variables.tf
```hcl
variable "name_prefix" {
  description = "리소스 이름 접두사"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR 블록"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "퍼블릭 서브넷 CIDR 목록"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "프라이빗 서브넷 CIDR 목록"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.20.0/24"]
}

variable "enable_nat_gateway" {
  description = "NAT Gateway 활성화"
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "EKS 클러스터 이름"
  type        = string
}

variable "tags" {
  description = "리소스 태그"
  type        = map(string)
  default     = {}
}
```

### modules/vpc/outputs.tf
```hcl
output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}
```

---

## 🔒 3단계: Security Groups 모듈

### modules/security-groups/main.tf
```hcl
# EKS Control Plane 보안 그룹
resource "aws_security_group" "eks_control_plane" {
  name_prefix = "${var.name_prefix}-eks-control-plane"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_worker_nodes.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-eks-control-plane-sg"
  })
}

# EKS Worker Nodes 보안 그룹
resource "aws_security_group" "eks_worker_nodes" {
  name_prefix = "${var.name_prefix}-eks-worker-nodes"
  vpc_id      = var.vpc_id

  # 워커 노드 간 통신
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  # Control plane → Worker nodes
  ingress {
    from_port       = 1025
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_control_plane.id]
  }

  # ALB → Worker nodes
  ingress {
    from_port       = 30000
    to_port         = 32767
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-eks-worker-nodes-sg"
  })
}

# ALB 보안 그룹
resource "aws_security_group" "alb" {
  name_prefix = "${var.name_prefix}-alb"
  vpc_id      = var.vpc_id

  # 인터넷 → ALB
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

  # ALB → Worker nodes
  egress {
    from_port       = 30000
    to_port         = 32767
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_worker_nodes.id]
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-alb-sg"
  })
}
```

---

## ⚙️ 4단계: EKS 모듈

### modules/eks/main.tf
```hcl
# EKS 클러스터
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = var.cluster_service_role_arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids             = concat(var.public_subnet_ids, var.private_subnet_ids)
    endpoint_private_access = true
    endpoint_public_access  = true
    security_group_ids     = [var.cluster_security_group_id]
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  tags = var.tags
}

# 기본 Node Group
resource "aws_eks_node_group" "primary" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-primary-nodes"
  node_role_arn   = var.node_group_role_arn
  subnet_ids      = var.private_subnet_ids

  capacity_type  = "ON_DEMAND"
  instance_types = var.node_instance_types

  scaling_config {
    desired_size = var.node_desired_size
    max_size     = var.node_max_size
    min_size     = var.node_min_size
  }

  disk_size = 20

  tags = var.tags
}

# Spot Instance Node Group
resource "aws_eks_node_group" "spot" {
  count = var.enable_spot_nodes ? 1 : 0

  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-spot-nodes"
  node_role_arn   = var.node_group_role_arn
  subnet_ids      = var.private_subnet_ids

  capacity_type  = "SPOT"
  instance_types = ["t3.medium", "t3.large"]

  scaling_config {
    desired_size = 1
    max_size     = 3
    min_size     = 0
  }

  taint {
    key    = "spot"
    value  = "true"
    effect = "NO_SCHEDULE"
  }

  tags = var.tags
}

# EKS Add-ons
resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "vpc-cni"
}

resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "coredns"
  depends_on   = [aws_eks_node_group.primary]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "kube-proxy"
}
```

### modules/eks/variables.tf
```hcl
variable "cluster_name" {
  description = "EKS 클러스터 이름"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes 버전"
  type        = string
  default     = "1.28"
}

variable "cluster_service_role_arn" {
  description = "EKS 클러스터 서비스 역할 ARN"
  type        = string
}

variable "node_group_role_arn" {
  description = "노드 그룹 역할 ARN"
  type        = string
}

variable "cluster_security_group_id" {
  description = "클러스터 보안 그룹 ID"
  type        = string
}

variable "public_subnet_ids" {
  description = "퍼블릭 서브넷 ID 목록"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "프라이빗 서브넷 ID 목록"
  type        = list(string)
}

variable "node_instance_types" {
  description = "노드 인스턴스 타입"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "노드 원하는 개수"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "노드 최대 개수"
  type        = number
  default     = 4
}

variable "node_min_size" {
  description = "노드 최소 개수"
  type        = number
  default     = 1
}

variable "enable_spot_nodes" {
  description = "Spot 인스턴스 노드 그룹 활성화"
  type        = bool
  default     = false
}

variable "tags" {
  description = "리소스 태그"
  type        = map(string)
  default     = {}
}
```

---

## 👤 5단계: IAM 모듈

### modules/iam/main.tf
```hcl
# EKS 클러스터 서비스 역할
resource "aws_iam_role" "eks_cluster" {
  name = "${var.name_prefix}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

# EKS 노드 그룹 역할
resource "aws_iam_role" "eks_node_group" {
  name = "${var.name_prefix}-eks-node-group-role"

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

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_group.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_group.name
}

resource "aws_iam_role_policy_attachment" "eks_container_registry_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_group.name
}
```

### modules/iam/outputs.tf
```hcl
output "eks_cluster_role_arn" {
  value = aws_iam_role.eks_cluster.arn
}

output "eks_node_group_role_arn" {
  value = aws_iam_role.eks_node_group.arn
}
```

---

## 🌍 6단계: 환경별 설정 (Dev)

### environments/dev/main.tf
```hcl
terraform {
  required_version = ">= 1.5"
  
  backend "s3" {
    bucket         = "openwebui-terraform-state-xxxx"  # 실제 버킷명으로 변경
    key            = "dev/terraform.tfstate"
    region         = "ap-northeast-2"
    dynamodb_table = "openwebui-terraform-lock"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# IAM 모듈
module "iam" {
  source = "../../modules/iam"
  
  name_prefix = local.name_prefix
  tags        = local.common_tags
}

# VPC 모듈
module "vpc" {
  source = "../../modules/vpc"
  
  name_prefix            = local.name_prefix
  cluster_name           = var.cluster_name
  vpc_cidr              = var.vpc_cidr
  public_subnet_cidrs   = var.public_subnet_cidrs
  private_subnet_cidrs  = var.private_subnet_cidrs
  enable_nat_gateway    = var.enable_nat_gateway
  tags                  = local.common_tags
}

# Security Groups 모듈
module "security_groups" {
  source = "../../modules/security-groups"
  
  name_prefix = local.name_prefix
  vpc_id      = module.vpc.vpc_id
  tags        = local.common_tags
}

# EKS 모듈
module "eks" {
  source = "../../modules/eks"
  
  cluster_name                = var.cluster_name
  kubernetes_version         = var.kubernetes_version
  cluster_service_role_arn   = module.iam.eks_cluster_role_arn
  node_group_role_arn        = module.iam.eks_node_group_role_arn
  cluster_security_group_id  = module.security_groups.eks_control_plane_sg_id
  public_subnet_ids          = module.vpc.public_subnet_ids
  private_subnet_ids         = module.vpc.private_subnet_ids
  node_instance_types        = var.node_instance_types
  node_desired_size          = var.node_desired_size
  node_max_size              = var.node_max_size
  node_min_size              = var.node_min_size
  enable_spot_nodes          = var.enable_spot_nodes
  tags                       = local.common_tags
}
```

### environments/dev/variables.tf
```hcl
variable "aws_region" {
  description = "AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "project_name" {
  description = "프로젝트 이름"
  type        = string
  default     = "openwebui"
}

variable "environment" {
  description = "환경 (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "cluster_name" {
  description = "EKS 클러스터 이름"
  type        = string
  default     = "openwebui-eks-dev"
}

variable "kubernetes_version" {
  description = "Kubernetes 버전"
  type        = string
  default     = "1.28"
}

variable "vpc_cidr" {
  description = "VPC CIDR 블록"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "퍼블릭 서브넷 CIDR 목록"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "프라이빗 서브넷 CIDR 목록"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.20.0/24"]
}

variable "enable_nat_gateway" {
  description = "NAT Gateway 활성화"
  type        = bool
  default     = true
}

variable "node_instance_types" {
  description = "노드 인스턴스 타입"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "노드 원하는 개수"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "노드 최대 개수"
  type        = number
  default     = 4
}

variable "node_min_size" {
  description = "노드 최소 개수"
  type        = number
  default     = 1
}

variable "enable_spot_nodes" {
  description = "Spot 인스턴스 노드 그룹 활성화"
  type        = bool
  default     = false
}
```

### environments/dev/terraform.tfvars
```hcl
# 개발 환경 설정
project_name    = "openwebui"
environment     = "dev"
cluster_name    = "openwebui-eks-dev"
aws_region      = "ap-northeast-2"

# 네트워크 설정
vpc_cidr                = "10.0.0.0/16"
public_subnet_cidrs     = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs    = ["10.0.10.0/24", "10.0.20.0/24"]
enable_nat_gateway      = true

# EKS 설정
kubernetes_version      = "1.28"
node_instance_types     = ["t3.medium"]
node_desired_size       = 2
node_max_size           = 4
node_min_size           = 1
enable_spot_nodes       = false
```

---

## 🔧 7단계: 배포 스크립트

### scripts/init.sh
```bash
#!/bin/bash
set -e

ENV=${1:-dev}
echo "🚀 Initializing Terraform for environment: $ENV"

cd "environments/$ENV"

# Terraform 초기화
terraform init

# Workspace 생성/선택
terraform workspace new $ENV 2>/dev/null || terraform workspace select $ENV

echo "✅ Terraform initialized for $ENV environment"
```

### scripts/plan.sh
```bash
#!/bin/bash
set -e

ENV=${1:-dev}
echo "📋 Planning Terraform for environment: $ENV"

cd "environments/$ENV"
terraform plan -var-file="terraform.tfvars" -out="$ENV.tfplan"

echo "✅ Terraform plan completed for $ENV environment"
```

### scripts/apply.sh
```bash
#!/bin/bash
set -e

ENV=${1:-dev}
echo "🚀 Applying Terraform for environment: $ENV"

cd "environments/$ENV"

# Plan이 존재하는지 확인
if [ ! -f "$ENV.tfplan" ]; then
  echo "❌ Plan file not found. Run plan.sh first."
  exit 1
fi

terraform apply "$ENV.tfplan"

echo "✅ Terraform applied for $ENV environment"
```

### scripts/destroy.sh
```bash
#!/bin/bash
set -e

ENV=${1:-dev}
echo "🗑️  Destroying Terraform for environment: $ENV"

read -p "Are you sure you want to destroy $ENV environment? (yes/no): " confirmation

if [ "$confirmation" != "yes" ]; then
  echo "❌ Destruction cancelled"
  exit 1
fi

cd "environments/$ENV"
terraform destroy -var-file="terraform.tfvars" -auto-approve

echo "✅ Terraform destroyed for $ENV environment"
```

---

## 🚀 배포 실행

### 1. 백엔드 설정
```bash
cd terraform/backend
terraform init
terraform apply
```

### 2. 개발 환경 배포
```bash
cd terraform

# 초기화
./scripts/init.sh dev

# 계획 확인
./scripts/plan.sh dev

# 배포 실행
./scripts/apply.sh dev
```

### 3. kubectl 설정
```bash
aws eks update-kubeconfig --region ap-northeast-2 --name openwebui-eks-dev
kubectl get nodes
```

---

## 💰 비용 최적화 팁

### 개발 환경 비용 절약
```hcl
# terraform.tfvars에서
enable_nat_gateway = false      # NAT Gateway 비용 절약 (-$64/월)
enable_spot_nodes = true        # Spot 인스턴스 사용 (-70% 할인)
node_desired_size = 1           # 최소 노드 수 운영
```

### 리소스 정리 자동화
```bash
# 매일 밤 리소스 정리 (개발환경)
crontab -e
0 22 * * * cd /path/to/terraform && ./scripts/destroy.sh dev
0 8 * * * cd /path/to/terraform && ./scripts/apply.sh dev
```

---

## 🔍 트러블슈팅

### 자주 발생하는 오류

#### 1. IAM 권한 부족
```bash
Error: AccessDenied: User is not authorized to perform: eks:CreateCluster
```
**해결:** IAM 사용자에게 EKS 관련 권한 추가

#### 2. 서브넷 CIDR 충돌
```bash
Error: InvalidVpcID.NotFound
```
**해결:** VPC CIDR와 서브넷 CIDR 확인

#### 3. 노드 그룹 생성 실패
```bash
Error: NodeCreationFailure
```
**해결:** 프라이빗 서브넷에 NAT Gateway 라우트 확인

---

## ⏭️ 다음 단계

인프라 배포가 완료되었다면:
- **[04-eks-deployment.md]** - 애플리케이션 배포
- **[05-cicd-pipeline.md]** - CI/CD 파이프라인 설정
