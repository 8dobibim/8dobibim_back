# 🏗️ 실제 프로젝트 기반 Terraform 구성 가이드

> **⏱️ 예상 소요시간**: 60-90분  
> **💡 난이도**: 중급  
> **📋 목표**: Terraform을 사용하여 AWS EKS 클러스터와 애플리케이션 스택 구축  
> **📁 전체 코드**: [GitHub에서 확인하기](https://github.com/8dobibim/combined/tree/main/8dobibim_back/terraform-related/AWS_terraform_grafana)

---

## 📁 프로젝트 구조

```
terraform-related/
└── AWS_terraform_grafana/
    ├── main.tf           # 메인 리소스 정의
    ├── variables.tf      # 변수 선언
    ├── versions.tf       # 프로바이더 버전
    ├── terraform.tfvars  # 변수 값 (Git 제외)
    └── tfvars.example    # 변수 예시 파일
```

---

## 🔧 Step 1: 프로바이더 및 버전 설정

### versions.tf
```hcl
terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.23.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "5.45.0"
    }
  }
}
```

**🔍 설명**:
- AWS와 Kubernetes 프로바이더 사용
- 버전을 고정하여 일관성 보장

---

## 🌐 Step 2: 네트워크 인프라 구성

### 2-1. 프로바이더 설정
```hcl
provider "aws" {
  region  = var.aws_region
  profile = "llm"  # AWS CLI 프로파일 사용
}

# EKS 인증 정보
data "aws_eks_cluster_auth" "main" {
  name = aws_eks_cluster.main.name
}

# Kubernetes 프로바이더 (EKS 연동)
provider "kubernetes" {
  alias                  = "eks"
  host                   = aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.main.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.main.token
}
```

**🔍 설명**:
- `profile`: AWS CLI에 설정된 프로파일 사용
- EKS 클러스터 생성 후 자동으로 인증 정보 가져옴
- Kubernetes 프로바이더는 EKS 엔드포인트와 연동

### 2-2. VPC 생성
```hcl
resource "aws_vpc" "main" {
  cidr_block = "10.38.0.0/16"

  tags = {
    Name = "llm-project-eks-vpc"
  }
}
```

**🔍 설명**:
- 전용 VPC 생성 (10.38.0.0/16 대역)
- 충분한 IP 주소 공간 확보 (65,536개)

### 2-3. 서브넷 구성
```hcl
# 서브넷 1 (가용영역 2b)
resource "aws_subnet" "subnet_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.38.1.0/24"
  availability_zone       = "ap-northeast-2b"
  map_public_ip_on_launch = true
  
  tags = {
    Name = "llm-subnet-1"
  }
}

# 서브넷 2 (가용영역 2c)
resource "aws_subnet" "subnet_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.38.2.0/24"
  availability_zone       = "ap-northeast-2c"
  map_public_ip_on_launch = true
  
  tags = {
    Name = "llm-subnet-2"
  }
}
```

**🔍 설명**:
- 2개의 가용영역에 서브넷 배치 (고가용성)
- Public IP 자동 할당 설정
- 각 서브넷은 256개의 IP 주소 제공

### 2-4. 인터넷 연결 설정
```hcl
# 인터넷 게이트웨이
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "llm-project-eks-igw"
  }
}

# 라우팅 테이블
resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "llm-project-eks-rt"
  }
}

# 서브넷과 라우팅 테이블 연결
resource "aws_route_table_association" "subnet_1" {
  subnet_id      = aws_subnet.subnet_1.id
  route_table_id = aws_route_table.main.id
}

resource "aws_route_table_association" "subnet_2" {
  subnet_id      = aws_subnet.subnet_2.id
  route_table_id = aws_route_table.main.id
}
```

**🔍 설명**:
- 인터넷 게이트웨이로 외부 통신 활성화
- 모든 외부 트래픽(0.0.0.0/0)을 IGW로 라우팅

---

## 🔒 Step 3: 보안 그룹 설정

### 3-1. EKS 클러스터 보안 그룹
```hcl
resource "aws_security_group" "eks_cluster_sg" {
  name        = "llm-project-eks-sg"
  description = "Security group for EKS cluster"
  vpc_id      = aws_vpc.main.id

  # VPC 내부 통신 허용
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.38.0.0/16"]
  }

  # 모든 아웃바운드 허용
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

### 3-2. 애플리케이션별 포트 개방
```hcl
# Grafana 포트 (3000-3001)
resource "aws_security_group_rule" "allow_openwebui_grafana" {
  type              = "ingress"
  from_port         = 3000
  to_port           = 3001
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.eks_cluster_sg.id
}

# Prometheus 포트 (9090)
resource "aws_security_group_rule" "allow_prometheus" {
  type              = "ingress"
  from_port         = 9090
  to_port           = 9090
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.eks_cluster_sg.id
}
```

**🔍 설명**:
- VPC 내부는 모든 포트 통신 허용
- 특정 서비스 포트만 인터넷에서 접근 가능

---

## 👤 Step 4: IAM 역할 설정

### 4-1. EKS 클러스터 역할
```hcl
resource "aws_iam_role" "eks_cluster_role" {
  name = "llm-project-eks-eks-cluster-role-v3"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "eks.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

# EKS 클러스터 정책 연결
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}
```

### 4-2. 노드 그룹 역할
```hcl
resource "aws_iam_role" "eks_node_role" {
  name = "llm-project-eks-eks-node-role-v3"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

# 필수 정책 연결
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_container_registry_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_role.name
}

# EBS CSI 드라이버 정책 (영구 스토리지용)
resource "aws_iam_role_policy_attachment" "ebs_csi_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.eks_node_role.name
}
```

**🔍 설명**:
- EKS 클러스터와 노드에 필요한 최소 권한만 부여
- EBS CSI 드라이버로 영구 볼륨 사용 가능

---

## ⚙️ Step 5: EKS 클러스터 구성

### 5-1. EKS 클러스터 생성
```hcl
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    security_group_ids      = [aws_security_group.eks_cluster_sg.id]
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  kubernetes_network_config {
    service_ipv4_cidr = "172.20.0.0/16"
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]
}
```

**🔍 설명**:
- Private/Public 엔드포인트 모두 활성화
- 서비스 네트워크는 172.20.0.0/16 사용 (VPC와 겹치지 않음)

### 5-2. 노드 그룹 생성
```hcl
resource "aws_eks_node_group" "nodes" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-nodes"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = var.private_subnet_ids
  instance_types  = [var.instance_type]
  
  scaling_config {
    desired_size = var.node_group_desired_capacity
    min_size     = var.node_group_min_capacity
    max_size     = var.node_group_max_capacity
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_container_registry_policy,
    aws_iam_role_policy_attachment.ebs_csi_policy
  ]
}
```

**🔍 설명**:
- 오토스케일링 설정 (1~3개 노드)
- t3.xlarge 인스턴스 사용 (4 vCPU, 16GB RAM)

### 5-3. EKS 애드온 설치
```hcl
resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "aws-ebs-csi-driver"
  
  depends_on = [
    aws_eks_cluster.main,
    aws_iam_role_policy_attachment.ebs_csi_policy
  ]
}
```

---

## 🐘 Step 6: PostgreSQL 데이터베이스 구성

### 6-1. 영구 볼륨 클레임
```hcl
resource "kubernetes_persistent_volume_claim" "postgres_pvc" {
  provider   = kubernetes.eks
  depends_on = [
    aws_eks_node_group.nodes,
    aws_eks_addon.ebs_csi_driver
  ]

  metadata {
    name      = "postgres-pvc"
    namespace = var.namespace
  }

  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = { storage = "5Gi" }
    }
    storage_class_name = "gp2-immediate"
  }
}
```

### 6-2. PostgreSQL 배포
```hcl
resource "kubernetes_deployment" "postgres_deployment" {
  provider   = kubernetes.eks
  depends_on = [
    aws_eks_node_group.nodes,
    kubernetes_persistent_volume_claim.postgres_pvc
  ]

  metadata {
    name      = "postgres"
    namespace = var.namespace
    labels = {
      app = "postgres"
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "postgres"
      }
    }

    template {
      metadata {
        labels = {
          app = "postgres"
        }
      }

      spec {
        container {
          name  = "postgres"
          image = "postgres:13"

          env {
            name  = "POSTGRES_DB"
            value = var.postgres_db
          }
          env {
            name  = "POSTGRES_USER"
            value = var.postgres_user
          }
          env {
            name  = "POSTGRES_PASSWORD"
            value = var.postgres_password
          }
          env {
            name  = "PGDATA"
            value = "/var/lib/postgresql/data/pgdata"
          }
          
          port {
            container_port = 5432
          }

          volume_mount {
            mount_path = "/var/lib/postgresql/data"
            name       = "postgres-storage"
          }
        }

        volume {
          name = "postgres-storage"
          persistent_volume_claim {
            claim_name = "postgres-pvc"
          }
        }
      }
    }
  }
}
```

### 6-3. PostgreSQL 서비스
```hcl
resource "kubernetes_service" "postgres_service" {
  provider   = kubernetes.eks
  depends_on = [aws_eks_node_group.nodes]

  metadata {
    name      = "postgres-service"
    namespace = var.namespace
  }

  spec {
    selector = {
      app = "postgres"
    }
    port {
      port        = 5432
      target_port = 5432
    }
    type = "ClusterIP"
  }
}
```

**🔍 설명**:
- 5GB EBS 볼륨으로 데이터 영구 저장
- ClusterIP로 내부 통신만 허용
- PGDATA 경로를 서브디렉토리로 설정 (권한 문제 방지)

---

## 🤖 Step 7: LiteLLM 프록시 구성

### 7-1. LiteLLM 배포
```hcl
resource "kubernetes_deployment" "litellm_deployment" {
  provider   = kubernetes.eks
  depends_on = [aws_eks_node_group.nodes]

  metadata {
    name      = "litellm"
    namespace = var.namespace
    labels = {
      app = "litellm"
    }
  }
  
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "litellm"
      }
    }
    
    template {
      metadata {
        labels = {
          app = "litellm"
        }
      }
      
      spec {
        container {
          name  = "litellm"
          image = "ghcr.io/berriai/litellm:main"
          
          # Azure OpenAI 설정
          env {
            name  = "AZURE_API_KEY"
            value = var.AZURE_API_KEY
          }
          env {
            name  = "AZURE_OPENAI_API_KEY"
            value = var.AZURE_API_KEY
          }
          env {
            name  = "AZURE_API_BASE"
            value = var.AZURE_API_BASE
          }
          env {
            name  = "AZURE_API_VERSION"
            value = var.AZURE_API_VERSION
          }
          
          # Gemini API 설정
          env {
            name  = "GEMINI_API_KEY"
            value = var.GEMINI_API_KEY
          }
          
          # 데이터베이스 및 인증
          env {
            name  = "DATABASE_URL"
            value = var.database_url
          }
          env {
            name  = "LITELLM_MASTER_KEY"
            value = var.litellm_master_key
          }
          env {
            name  = "LITELLM_SALT_KEY"
            value = var.litellm_salt_key
          }
          
          port {
            container_port = var.litellm_api_port      # 4000
          }
          port {
            container_port = var.litellm_metrics_port  # 8000
          }
        }
      }
    }
  }
}
```

### 7-2. LiteLLM 서비스 (LoadBalancer)
```hcl
resource "kubernetes_service" "litellm_service" {
  provider   = kubernetes.eks
  depends_on = [aws_eks_node_group.nodes]

  metadata {
    name      = "litellm-service"
    namespace = var.namespace
    annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-type"   = "nlb"
      "service.beta.kubernetes.io/aws-load-balancer-scheme" = "internet-facing"
    }
  }
  
  spec {
    selector = {
      app = "litellm"
    }
    port {
      name        = "api"
      protocol    = "TCP"
      port        = var.litellm_api_port
      target_port = var.litellm_api_port
    }
    port {
      name        = "metrics"
      protocol    = "TCP"
      port        = var.litellm_metrics_port
      target_port = var.litellm_metrics_port
    }
    type = "LoadBalancer"
  }
}
```

**🔍 설명**:
- 멀티 LLM 프록시 (Azure OpenAI, Gemini 지원)
- NLB(Network Load Balancer) 사용으로 낮은 지연시간
- API와 메트릭 포트 분리

---

## 🌐 Step 8: OpenWebUI 구성

### 8-1. OpenWebUI 배포
```hcl
resource "kubernetes_deployment" "openwebui_deployment" {
  provider   = kubernetes.eks
  depends_on = [aws_eks_node_group.nodes]

  metadata {
    name      = "openwebui"
    namespace = var.namespace
    labels = {
      app = "openwebui"
    }
  }
  
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "openwebui"
      }
    }
    
    template {
      metadata {
        labels = {
          app = "openwebui"
        }
      }
      
      spec {
        container {
          name  = "openwebui"
          image = "ghcr.io/open-webui/open-webui:main"
          command = ["uvicorn", "open_webui.main:app", "--host", "0.0.0.0", "--port", "3000"]
          
          env {
            name  = "DATABASE_URL"
            value = var.database_url
          }
          env {
            name  = "LITELLM_PROXY_BASE_URL"
            value = "http://litellm-service:${var.litellm_api_port}"
          }
          
          port {
            container_port = var.openwebui_port  # 3000
          }
        }
      }
    }
  }
}
```

### 8-2. OpenWebUI 서비스
```hcl
resource "kubernetes_service" "openwebui_service" {
  provider = kubernetes.eks
  depends_on = [aws_eks_node_group.nodes]

  metadata {
    name      = "openwebui-service"
    namespace = var.namespace
    annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-type"   = "classic"
      "service.beta.kubernetes.io/aws-load-balancer-scheme" = "internet-facing"
    }
  }
  
  spec {
    selector = {
      app = "openwebui"
    }
    port {
      protocol    = "TCP"
      port        = var.openwebui_port
      target_port = var.openwebui_port
    }
    type = "LoadBalancer"
  }
}
```

---

## 📊 Step 9: 모니터링 스택

### 9-1. Prometheus 배포
```hcl
resource "kubernetes_deployment" "prometheus_deployment" {
  provider   = kubernetes.eks
  depends_on = [aws_eks_node_group.nodes]

  metadata {
    name      = "prometheus"
    namespace = var.namespace
    labels = {
      app = "prometheus"
    }
  }
  
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "prometheus"
      }
    }
    
    template {
      metadata {
        labels = {
          app = "prometheus"
        }
      }
      
      spec {
        container {
          name  = "prometheus"
          image = "prom/prometheus:latest"
          port {
            container_port = var.prometheus_port  # 9090
          }
        }
      }
    }
  }
}
```

### 9-2. Grafana 배포
```hcl
resource "kubernetes_deployment" "grafana_deployment" {
  provider   = kubernetes.eks
  depends_on = [aws_eks_node_group.nodes]

  metadata {
    name      = "grafana"
    namespace = var.namespace
    labels = {
      app = "grafana"
    }
  }
  
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "grafana"
      }
    }
    
    template {
      metadata {
        labels = {
          app = "grafana"
        }
      }
      
      spec {
        container {
          name  = "grafana"
          image = "grafana/grafana:latest"
          port {
            container_port = var.grafana_port  # 3001
          }
        }
      }
    }
  }
}
```

---

## 📝 Step 10: 변수 설정

### variables.tf (주요 변수)
```hcl
variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "ap-northeast-2"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "llm-project-eks"
}

variable "instance_type" {
  description = "EC2 instance type for EKS worker nodes"
  type        = string
  default     = "t3.xlarge"
}

variable "node_group_desired_capacity" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 2
}

# API 키 변수들
variable "GEMINI_API_KEY" {
  description = "Gemini API key for LiteLLM"
  type        = string
  sensitive   = true
}

variable "AZURE_API_KEY" {
  description = "Azure OpenAI API key"
  type        = string
  sensitive   = true
}

# 데이터베이스 변수들
variable "postgres_user" {
  description = "PostgreSQL username"
  type        = string
  sensitive   = true
}

variable "postgres_password" {
  description = "PostgreSQL password"
  type        = string
  sensitive   = true
}
```

### terraform.tfvars.example
```hcl
# AWS 설정
aws_region = "ap-northeast-2"
cluster_name = "llm-project-eks"

# 네트워크 설정 (실제 값으로 변경 필요)
vpc_id = "vpc-0f11e0b7cb225055a"
private_subnet_ids = ["subnet-020d530cbcaed0656", "subnet-06bed7cfb33b120c1"]

# 노드 그룹 설정
instance_type = "t3.medium"
node_group_desired_capacity = 2
node_group_min_capacity = 1
node_group_max_capacity = 3

# 애플리케이션 포트
litellm_api_port = 4000
litellm_metrics_port = 8000
openwebui_port = 3000
prometheus_port = 9090
grafana_port = 3001

# 민감한 정보 (실제 값으로 변경 필수!)
# 이 값들은 환경 변수나 CI/CD 시크릿으로 관리
litellm_master_key = "<YOUR_MASTER_KEY>"
litellm_salt_key = "<YOUR_SALT_KEY>"
GEMINI_API_KEY = "<YOUR_GEMINI_KEY>"
AZURE_API_KEY = "<YOUR_AZURE_KEY>"
AZURE_API_BASE = "https://your-resource.openai.azure.com/"
AZURE_API_VERSION = "2023-07-01-preview"

# PostgreSQL 설정
postgres_user = "openwebui_user"
postgres_password = "<SECURE_PASSWORD>"
postgres_db = "openwebui"
database_url = "postgresql://openwebui_user:<PASSWORD>@postgres-service:5432/openwebui"
```

---

## 🚀 배포 실행 가이드

### 1. 사전 준비
```bash
# AWS CLI 프로파일 설정
aws configure --profile llm

# 작업 디렉토리 이동
cd terraform-related/AWS_terraform_grafana
```

### 2. 변수 파일 준비
```bash
# 예시 파일 복사
cp tfvars.example terraform.tfvars

# 실제 값으로 수정
vim terraform.tfvars
```

### 3. Terraform 실행
```bash
# 초기화
terraform init

# 계획 확인
terraform plan

# 배포 실행
terraform apply
```

### 4. kubectl 설정
```bash
# kubeconfig 업데이트
aws eks update-kubeconfig --region ap-northeast-2 --name llm-project-eks --profile llm

# 클러스터 확인
kubectl get nodes
kubectl get pods -A
```

### 5. 서비스 URL 확인
```bash
# LoadBalancer URL 확인
kubectl get svc -A | grep LoadBalancer

# 각 서비스별 엔드포인트
echo "OpenWebUI: http://$(kubectl get svc openwebui-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'):3000"
echo "Grafana: http://$(kubectl get svc grafana-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'):3001"
echo "Prometheus: http://$(kubectl get svc prometheus-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'):9090"
```

---

## 💰 비용 최적화 팁

### 개발 환경 설정
```hcl
# terraform.tfvars에서 조정
instance_type = "t3.small"              # 작은 인스턴스 사용
node_group_desired_capacity = 1         # 최소 노드로 운영
node_group_min_capacity = 0             # 야간 스케일다운 가능
```

### 리소스 정리
```bash
# 전체 리소스 삭제
terraform destroy

# 특정 리소스만 삭제
