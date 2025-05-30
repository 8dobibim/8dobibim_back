# main.tf - AWS EKS Deployment with OpenWebUI A/B Testing

# --- Providers Configuration ---
# AWS Provider: AWS 리소스를 생성 및 관리합니다.
provider "aws" {
  region = var.aws_region # variables.tf 에서 정의한 리전 사용
  # profile = "your-aws-profile" # 특정 AWS CLI 프로파일 사용 시 주석 해제 및 프로파일 이름 지정
  default_tags {
    tags = var.aws_tags # variables.tf 에서 정의한 기본 태그 적용
  }
}

# Kubernetes Provider: EKS 클러스터에 Kubernetes 리소스를 배포합니다.
# EKS 클러스터 생성 완료 후 그 정보를 사용하도록 설정합니다.
provider "kubernetes" {
  # 로컬 kubeconfig 파일 대신, Terraform으로 생성한 EKS 클러스터 정보 사용
  # OIDC Issuer URL 또는 Endpoint 사용
  host                   = aws_eks_cluster.main.identities[0].oidc[0].issuer
  cluster_ca_certificate = base64decode(aws_eks_cluster.main.certificate_authority[0].data)
  # EKS 클러스터 인증 토큰 Data Source 생성 후 사용
  token                  = data.aws_eks_cluster_auth.main.token

  # EKS 클러스터 및 인증 정보 Data Source 생성 완료 후 이 Provider 사용 가능
  depends_on = [
    aws_eks_cluster.main,
    data.aws_eks_cluster_auth.main,
  ]
}

# Helm Provider: EKS 클러스터에 Helm 차트를 배포합니다 (예: ALB Ingress Controller).
provider "helm" {
  # Kubernetes Provider와 동일하게 EKS 클러스터 정보 사용
  host = provider.kubernetes.host
  token = provider.kubernetes.token
  cluster_ca_certificate = provider.kubernetes.cluster_ca_certificate

  # Kubernetes Provider 설정 완료 후 Helm Provider 사용 가능
  depends_on = [
    provider.kubernetes,
  ]
}


# --- Data Sources ---
# EKS 클러스터와 연결하기 위해 현재 AWS 인증 정보를 사용합니다.
data "aws_eks_cluster_auth" "main" {
  name = aws_eks_cluster.main.name # 아래에서 정의할 EKS 클러스터 이름 참조
}

# 사용 가능한 가용 영역(AZ) 목록을 가져옵니다. Subnet 생성 시 사용합니다.
data "aws_availability_zones" "available" {}


# --- AWS Network Infrastructure ---
# 애플리케이션이 실행될 Virtual Private Cloud (VPC)를 정의합니다.
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr # variables.tf 에서 정의한 VPC CIDR 사용
  enable_dns_hostnames = true # EKS 동작에 필요
  enable_dns_support = true # EKS 동작에 필요

  tags = { Name = "${var.project_name}-vpc" }
}

# 인터넷 게이트웨이 (Public Subnet에서 인터넷 통신을 위해 필요)
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = { Name = "${var.project_name}-igw" }
}

# Public Subnets (ALB 및 Public Node 접근 - ALB Ingress Controller 사용 시 필요)
resource "aws_subnet" "public" {
  count = length(var.public_subnets_cidr) # variables.tf 에서 정의한 Public Subnet CIDR 개수만큼 생성

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnets_cidr[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index] # 사용 가능한 AZ에 자동 할당
  map_public_ip_on_launch = true # Public Subnet 이므로 Public IP 자동 할당 활성화

  tags = {
    Name = "${var.project_name}-public-subnet-${count.index + 1}"
    # ALB Ingress Controller가 Public Subnet을 찾도록 태그 추가 (중요)
    "kubernetes.io/cluster/${aws_eks_cluster.main.name}" = "owned" # 클러스터 이름 동적 참조
    "kubernetes.io/role/elb" = "1" # Public ALB용 Subnet임을 명시
  }
}

# Private Subnets (Backend Pod들이 위치. 인터넷 직접 접근 안됨 - EKS 노드 그룹 위치)
resource "aws_subnet" "private" {
  count = length(var.private_subnets_cidr) # variables.tf 에서 정의한 Private Subnet CIDR 개수만큼 생성

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnets_cidr[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index] # 사용 가능한 AZ에 자동 할당
  map_public_ip_on_launch = false # Private Subnet 이므로 Public IP 자동 할당 비활성화

  tags = {
    Name = "${var.project_name}-private-subnet-${count.index + 1}"
    # EKS 노드 그룹이 이 Subnet에 있다면 필요한 태그
    "kubernetes.io/cluster/${aws_eks_cluster.main.name}" = "owned" # 클러스터 이름 동적 참조
    "kubernetes.io/role/internal-elb" = "1" # Internal ALB용 Subnet임을 명시 (Internal ALB 사용 시)
  }
}

# Public Subnet 라우팅 테이블 (인터넷 게이트웨이 통해 인터넷 접근)
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0" # 모든 대상
    gateway_id = aws_internet_gateway.main.id # 인터넷 게이트웨이로 보냄
  }
  tags = { Name = "${var.project_name}-public-rt" }
}

# Public Subnet과 라우팅 테이블 연결
resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private Subnet을 위한 EIP (NAT Gateway용 Public IP)
resource "aws_eip" "nat" {
  count = length(var.private_subnets_cidr) # Private Subnet 개수만큼 NAT Gateway (권장 구성)
  domain = "vpc" # VPC용 EIP
  tags = { Name = "${var.project_name}-nat-eip-${count.index + 1}" }
}

# NAT Gateway (Private Subnet에서 인터넷으로 나갈 때 사용)
resource "aws_nat_gateway" "main" {
  count         = length(var.private_subnets_cidr)
  allocation_id = aws_eip.nat[count.index].id # 위에서 할당한 EIP 연결
  subnet_id     = aws_subnet.public[count.index].id # Public Subnet에 NAT Gateway 위치
  tags = { Name = "${var.project_name}-natgw-${count.index + 1}" }

  # EIP 및 Subnet 생성 후 의존성 명시 (불필요할 수 있지만 안전을 위해)
  depends_on = [aws_internet_gateway.main]
}

# Private Subnet 라우팅 테이블 (NAT Gateway 통해 인터넷 접근)
resource "aws_route_table" "private" {
  count  = length(var.private_subnets_cidr)
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0" # 모든 대상
    nat_gateway_id = aws_nat_gateway.main[count.index].id # 해당 AZ의 NAT Gateway로 보냄
  }
  tags = { Name = "${var.project_name}-private-rt-${count.index + 1}" }
}

# Private Subnet과 라우팅 테이블 연결
resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}


# --- EKS Cluster IAM Roles ---
# EKS 컨트롤 플레인이 AWS 리소스를 관리하기 위한 역할
resource "aws_iam_role" "eks_cluster_role" {
  name = "${var.project_name}-eks-cluster-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = { Service = "eks.amazonaws.com" } # EKS 서비스가 이 역할을Assume 가능
        Action = "sts:AssumeRole"
      },
    ]
  })
  tags = { Name = "${var.project_name}-eks-cluster-role" }
}

# EKS 클러스터 역할에 정책 연결
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role_name  = aws_iam_role.eks_cluster_role.name
}

# EKS 노드 그룹 (EC2 인스턴스)가 AWS 리소스를 관리하기 위한 역할
resource "aws_iam_role" "eks_node_group_role" {
  name = "${var.project_name}-eks-node-group-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = { Service = "ec2.amazonaws.com" } # EC2 서비스가 이 역할을 Assume 가능
        Action = "sts:AssumeRole"
      },
    ]
  })
  tags = { Name = "${var.project_name}-eks-node-group-role" }
}

# EKS 노드 역할에 정책 연결 (CNI, Worker Node, Registry Read)
resource "aws_iam_role_policy_attachment" "eks_node_group_policy_cni" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy" # VPC CNI 플러그인에 필요
  role_name  = aws_iam_role.eks_node_group_role.name
}

resource "aws_iam_role_policy_attachment" "eks_node_group_policy_worker" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy" # EKS 워커 노드 기본 정책
  role_name  = aws_iam_role.eks_node_group_role.name
}

resource "aws_iam_role_policy_attachment" "eks_node_group_policy_registry" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly" # ECR에서 이미지를 가져올 권한 (ghcr.io 사용 시 필수는 아님)
  role_name  = aws_iam_role.eks_node_group_role.name
}


# --- EKS Cluster ---
# EKS 클러스터 컨트롤 플레인 생성
resource "aws_eks_cluster" "main" {
  name     = "${var.project_name}-eks"
  version  = var.eks_cluster_version # variables.tf 에서 정의한 K8s 버전 사용
  role_arn = aws_iam_role.eks_cluster_role.arn # 위에서 정의한 클러스터 역할 연결

  vpc_config {
    # EKS 클러스터가 사용할 Public 및 Private Subnet IDs 지정
    # EKS API Endpoint는 Public or Private 으로 설정 가능
    subnet_ids = concat(aws_subnet.public[*].id, aws_subnet.private[*].id)
    # endpoint_private_access = true # Private Endpoint 만 사용 시 (보안 강화)
    # endpoint_public_access = true # Public Endpoint 사용 여부 (기본값 true)
  }

  # EKS 클러스터 생성 완료 후 OIDC Provider가 사용 가능해집니다.
  # ALB Ingress Controller IRSA 설정 시 필요
  # resource "aws_iam_openid_connect_provider" "main" { ... } # 별도로 OIDC Provider 리소스 정의 필요

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_route_table_association.public, # 네트워크 구성 완료 후 EKS 생성
    aws_route_table_association.private,
  ]

  tags = { Name = "${var.project_name}-eks" }
}

# EKS Node Group (EC2 워커 노드 그룹) 생성
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name # 위에서 정의한 클러스터 이름 참조
  node_group_name = "${var.project_name}-ng"
  node_role_arn   = aws_iam_role.eks_node_group_role.arn # 위에서 정의한 노드 역할 연결
  subnet_ids      = aws_subnet.private[*].id # 노드 그룹이 위치할 Private Subnet IDs 지정 (권장)

  instance_types = [var.eks_node_group_instance_type] # variables.tf 에서 정의한 인스턴스 타입
  disk_size      = 20 # 노드 디스크 크기 (GB), 필요시 조정

  scaling_config {
    desired_size = var.eks_node_group_desired_size # variables.tf 에서 정의한 노드 개수 (원하는 개수)
    max_size     = var.eks_node_group_max_size     # variables.tf 에서 정의한 노드 개수 (최대치)
    min_size     = var.eks_node_group_min_size     # variables.tf 에서 정의한 노드 개수 (최소치)
  }

  # EKS 클러스터 생성 완료 후 노드 그룹 생성
  depends_on = [
    aws_eks_cluster.main,
    aws_iam_role_policy_attachment.eks_node_group_policy_worker,
    aws_iam_role_policy_attachment.eks_node_group_policy_cni,
    aws_iam_role_policy_attachment.eks_node_group_policy_registry,
  ]

  tags = { Name = "${var.project_name}-eks-ng" }
}


# --- Kubernetes Namespace 생성 ---
# 애플리케이션 리소스가 배포될 네임스페이스
resource "kubernetes_namespace" "app_namespace" {
  metadata {
    name = var.namespace # variables.tf 에서 정의한 네임스페이스 사용
  }
  # Kubernetes Provider 설정 완료 후 네임스페이스 생성 가능
  depends_on = [
    provider.kubernetes,
    aws_eks_node_group.main, # 노드 그룹이 Ready 상태가 되어야 K8s API 가 안정적 (선택 사항)
  ]
}

# --- Secrets and ConfigMaps ---
# 민감 정보 (PostgreSQL, LLM API Keys 등)를 위한 Secret
resource "kubernetes_secret" "app_secrets" {
  metadata {
    name      = "app-secrets"
    namespace = kubernetes_namespace.app_namespace.metadata[0].name # 위에서 생성한 네임스페이스 참조
  }
  # data 블록에 변수에서 가져온 실제 값들을 포함 (자동 Base64 인코딩됨)
  # 사용자 코드의 대문자 변수 이름을 그대로 사용
  data = {
    "POSTGRES_USER"         = var.postgres_user
    "POSTGRES_PASSWORD"     = var.postgres_password
    "POSTGRES_DB"           = var.postgres_db
    "DATABASE_URL"          = var.DATABASE_URL # tfvars 에서 전체 URL로 설정했다면 이 변수 사용
    "LITELLM_MASTER_KEY"    = var.LITELLM_MASTER_KEY # 추가했다면 이 변수 사용
    "LITELLM_SALT_KEY"      = var.LITELLM_SALT_KEY # 추가했다면 이 변수 사용
    "GEMINI_API_KEY"        = var.GEMINI_API_KEY # 추가했다면 이 변수 사용
    "AZURE_API_KEY"         = var.AZURE_API_KEY # 추가했다면 이 변수 사용
    "AZURE_API_BASE"        = var.AZURE_API_BASE # 추가했다면 이 변수 사용
    "AZURE_API_VERSION"     = var.AZURE_API_VERSION # 추가했다면 이 변수 사용
    # ... 필요한 다른 민감 정보 변수들을 여기에 추가 ...
  }
  type = "Opaque" # 일반적인 키-값 쌍 Secret 타입

  # 네임스페이스 생성 완료 후 Secret 생성 가능
  depends_on = [
    kubernetes_namespace.app_namespace,
  ]
}

# LiteLLM 설정 파일 (config.yaml)을 위한 ConfigMap
resource "kubernetes_config_map" "litellm_config" {
  metadata {
    name      = "litellm-config"
    namespace = kubernetes_namespace.app_namespace.metadata[0].name # 네임스페이스 참조
  }
  data = {
    "config.yaml" = var.litellm_config_content # variables.tf 에서 정의한 설정 파일 내용 사용
  }
  depends_on = [ kubernetes_namespace.app_namespace ]
}

# Prometheus 설정 파일 (prometheus.yml)을 위한 ConfigMap
resource "kubernetes_config_map" "prometheus_config" {
  metadata {
    name      = "prometheus-config"
    namespace = kubernetes_namespace.app_namespace.metadata[0].name # 네임스페이스 참조
  }
  data = {
    "prometheus.yml" = var.prometheus_config_content # variables.tf 에서 정의한 설정 파일 내용 사용
  }
  depends_on = [ kubernetes_namespace.app_namespace ]
}

# --- PersistentVolumeClaims ---
# PostgreSQL 데이터의 영속성을 위한 PVC
resource "kubernetes_persistent_volume_claim" "postgres_pvc" {
  metadata {
    name      = "postgres-pvc"
    namespace = kubernetes_namespace.app_namespace.metadata[0].name # 네임스페이스 참조
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "5Gi" # 필요한 저장 공간 크기 설정
      }
    }
    # EKS는 기본 StorageClass를 제공합니다 (예: gp2 또는 gp3).
    # 특정 StorageClass를 사용하려면 이름을 명시합니다.
    # storage_class_name = "gp2" # 또는 "gp3" 등 EKS 클러스터의 StorageClass 이름 (variables.tf 변수로 관리 추천)
  }
  depends_on = [ kubernetes_namespace.app_namespace ]
}

# Prometheus 데이터의 영속성을 위한 PVC
resource "kubernetes_persistent_volume_claim" "prometheus_data_pvc" {
  metadata {
    name      = "prometheus-data-pvc"
    namespace = kubernetes_namespace.app_namespace.metadata[0].name # 네임스페이스 참조
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "10Gi" # Prometheus 데이터 저장 공간 (필요시 조정)
      }
    }
    # EKS 기본 StorageClass 사용
    # storage_class_name = "gp2"
  }
  depends_on = [ kubernetes_namespace.app_namespace ]
}


# --- Deployments ---
# PostgreSQL Deployment
resource "kubernetes_deployment" "postgres_deployment" {
  metadata {
    name      = "postgres"
    namespace = kubernetes_namespace.app_namespace.metadata[0].name # 네임스페이스 참조
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "postgres"
      }
    }
    strategy {
      type = "Recreate"
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
          image = var.postgres_image
          port {
            container_port = var.postgres_port
          }
          # Secret에서 환경 변수 주입 (POSTGRES_USER, POSTGRES_PASSWORD 등)
          env_from {
            secret_ref {
              name = kubernetes_secret.app_secrets.metadata[0].name # Secret 참조
            }
          }
          # DATABASE_URL 환경 변수는 env_from 에서 주입됩니다.
          # env { name = "DATABASE_URL"; value = "..." } # 이 블록은 이제 삭제

          volume_mount {
            name       = "postgres-storage"
            mount_path = "/var/lib/postgresql/data"
          }
          # Health checks (프로덕션 권장)
          /*
          liveness_probe { ... }
          readiness_probe { ... }
          */
        }
        volume {
          name = "postgres-storage"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.postgres_pvc.metadata[0].name # PVC 참조
          }
        }
      }
    }
  }
  depends_on = [
    kubernetes_namespace.app_namespace,
    kubernetes_secret.app_secrets,
    kubernetes_persistent_volume_claim.postgres_pvc,
  ]
}

# LiteLLM Deployment
resource "kubernetes_deployment" "litellm_deployment" {
  metadata {
    name      = "litellm"
    namespace = kubernetes_namespace.app_namespace.metadata[0].name # 네임스페이스 참조
    annotations = {
      # Prometheus가 이 Pod를 스크랩하도록 설정 (Prometheus config와 연동)
      "prometheus.io/scrape" = "true"
      "prometheus.io/path"   = "/metrics" # LiteLLM이 노출하는 metrics path
      "prometheus.io/port"   = "${var.litellm_metrics_port}"
    }
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "litellm"
      }
    }
     strategy {
       type = "RollingUpdate"
       rolling_update {
         max_unavailable = "25%"
         max_surge       = "25%"
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
          image = var.litellm_image
          args = [
            "--config", "/app/config/config.yaml",
            "--host", "0.0.0.0",
            "--port", "${var.litellm_api_port}",
            "--telemetry", "False"
            # --prometheus_url, --prometheus_port 등 필요 시 args나 env로 설정
          ]
          port {
            name = "api"
            container_port = var.litellm_api_port
          }
          port {
            name = "metrics"
            container_port = var.litellm_metrics_port
          }
          # Secret에서 환경 변수 주입 (LLM API 키, Master Key, DATABASE_URL 등)
          # env_from 을 사용하면 Secret 의 모든 키-값 쌍이 환경 변수로 주입됩니다.
          env_from {
            secret_ref {
              name = kubernetes_secret.app_secrets.metadata[0].name # Secret 참조
            }
          }
          # env_from 에 포함되지 않는 개별 환경 변수들은 여기에 추가
          env {
             name = "STORE_MODEL_IN_DB"
             value = "True"
           }

          # ConfigMap에서 config.yaml 파일 마운트
          volume_mount {
            name       = "litellm-config-volume"
            mount_path = "/app/config"
          }
        }
        volume {
          name = "litellm-config-volume"
          config_map {
            name = kubernetes_config_map.litellm_config.metadata[0].name # ConfigMap 참조
            items {
              key  = "config.yaml"
              path = "config.yaml"
            }
          }
        }
      }
    }
  }
  depends_on = [
    kubernetes_namespace.app_namespace,
    kubernetes_secret.app_secrets,
    kubernetes_config_map.litellm_config,
    # Kubernetes Service 는 Deployment 보다 먼저 생성되어야 함
  ]
}

# OpenWebUI Deployment (Version 1)
resource "kubernetes_deployment" "openwebui_deployment_v1" {
  metadata {
    name      = "openwebui-v1"
    namespace = kubernetes_namespace.app_namespace.metadata[0].name # 네임스페이스 참조
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app     = "openwebui"
        version = "v1" # 버전 구분을 위한 라벨 유지
      }
    }
     strategy {
       type = "RollingUpdate"
       rolling_update {
         max_unavailable = "25%"
         max_surge       = "25%"
       }
    }
    template {
      metadata {
        labels = {
          app     = "openwebui"
          version = "v1" # Pod에도 라벨 유지
        }
      }
      spec {
        container {
          name  = "openwebui"
          image = var.openwebui_image_v1 # v1 이미지
          port {
            container_port = var.openwebui_port
          }
          # OpenWebUI는 LiteLLM Service 에 연결합니다.
          env {
            name = "OLLAMA_BASE_URL"
            # LiteLLM 서비스의 ClusterIP 주소 사용 (내부 통신)
            value = "http://litellm-service:${var.litellm_api_port}"
          }
          # OpenWebUI가 필요로 하는 기타 환경 변수 (예: 기본 모델 설정)
          env {
             name = "DEFAULT_MODELS"
             value = "gemini-2.0-flash" # OpenWebUI 설정에 맞는 기본 모델 이름 설정
           }
          # OpenWebUI Pod에 직접 LLM API 키를 주입하지 마세요 (LiteLLM 에서 관리)
        }
      }
    }
  }
  depends_on = [
    kubernetes_namespace.app_namespace,
    # Kubernetes Service 는 Deployment 보다 먼저 생성되어야 함
  ]
}

# OpenWebUI Deployment (Version 2)
resource "kubernetes_deployment" "openwebui_deployment_v2" {
  metadata {
    name      = "openwebui-v2"
    namespace = kubernetes_namespace.app_namespace.metadata[0].name # 네임스페이스 참조
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app     = "openwebui"
        version = "v2" # 버전 구분을 위한 라벨 유지
      }
    }
     strategy {
       type = "RollingUpdate"
       rolling_update {
         max_unavailable = "25%"
         max_surge       = "25%"
       }
    }
    template {
      metadata {
        labels = {
          app     = "openwebui"
          version = "v2" # Pod에도 라벨 유지
        }
      }
      spec {
        container {
          name  = "openwebui"
          image = var.openwebui_image_v2 # v2 이미지
          port {
            container_port = var.openwebui_port
          }
          # OpenWebUI는 LiteLLM Service 에 연결합니다.
          env {
            name = "OLLAMA_BASE_URL"
            # LiteLLM 서비스의 ClusterIP 주소 사용 (내부 통신)
            value = "http://litellm-service:${var.litellm_api_port}"
          }
           # OpenWebUI가 필요로 하는 기타 환경 변수 (예: 기본 모델 설정)
           env {
             name = "DEFAULT_MODELS"
             value = "gpt-3.5-turbo" # OpenWebUI 설정에 맞는 기본 모델 이름 설정 (v1과 다르게 설정 가능)
           }
          # OpenWebUI Pod에 직접 LLM API 키를 주입하지 마세요 (LiteLLM 에서 관리)
        }
      }
    }
  }
   depends_on = [
    kubernetes_namespace.app_namespace,
    # Kubernetes Service 는 Deployment 보다 먼저 생성되어야 함
  ]
}

# Prometheus Deployment
resource "kubernetes_deployment" "prometheus_deployment" {
  metadata {
    name      = "prometheus"
    namespace = kubernetes_namespace.app_namespace.metadata[0].name # 네임스페이스 참조
    annotations = {
      # Prometheus가 이 Pod를 스크랩하도록 설정 (Prometheus config와 연동)
      "prometheus.io/scrape" = "true"
      "prometheus.io/path"   = "/metrics" # LiteLLM이 노출하는 metrics path
      "prometheus.io/port"   = "${var.litellm_metrics_port}"
    }
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "prometheus"
      }
    }
     strategy {
       type = "RollingUpdate"
       rolling_update {
         max_unavailable = "25%"
         max_surge       = "25%"
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
          image = var.prometheus_image
          args = [
            "--config.file=/etc/prometheus/prometheus.yml",
            "--storage.tsdb.path=/prometheus",
            "--web.console.libraries=/usr/share/prometheus/console_libraries",
            "--web.console.templates=/usr/share/prometheus/consoles"
          ]
          port {
            container_port = var.prometheus_port
          }
          volume_mount {
            name       = "prometheus-config-volume"
            mount_path = "/etc/prometheus"
          }
          # 데이터 지속성을 위한 볼륨 마운트 (EKS 환경에서는 PVC 권장)
           volume_mount {
             name = "prometheus-data"
             mount_path = "/prometheus"
           }
        }
        volume {
          name = "prometheus-config-volume"
          config_map {
            name = kubernetes_config_map.prometheus_config.metadata[0].name # ConfigMap 참조
          }
        }
        # 데이터 지속성을 위한 PVC (Prometheus 데이터용)
        volume {
           name = "prometheus-data"
           persistent_volume_claim {
             claim_name = kubernetes_persistent_volume_claim.prometheus_data_pvc.metadata[0].name # 위에서 정의한 PVC 참조
           }
         }
      }
    }
  }
   depends_on = [
    kubernetes_namespace.app_namespace,
    kubernetes_config_map.prometheus_config,
    kubernetes_persistent_volume_claim.prometheus_data_pvc, # PVC 가 먼저 생성되어야 함
   ]
}


# --- Services ---
# PostgreSQL Service (ClusterIP: 클러스터 내부 통신용)
resource "kubernetes_service" "postgres_service" {
  metadata {
    name      = "postgres-service" # LiteLLM에서 접근할 서비스 이름
    namespace = kubernetes_namespace.app_namespace.metadata[0].name # 네임스페이스 참조
  }
  spec {
    selector = {
      app = kubernetes_deployment.postgres_deployment.spec[0].selector[0].match_labels.app # .selector 뒤에 [0] 추가
    }
    port {
      protocol    = "TCP"
      port        = var.postgres_port
      target_port = var.postgres_port
    }
    type = "ClusterIP" # 클러스터 내부에서만 접근 가능
  }
  depends_on = [ kubernetes_deployment.postgres_deployment ]
}

# LiteLLM Service (ClusterIP: 클러스터 내부 통신용 - OpenWebUI, Prometheus 접근)
# 사용자에게 직접 노출하려면 Ingress 또는 다른 LoadBalancer Service 를 사용해야 합니다.
resource "kubernetes_service" "litellm_service" {
  metadata {
    name      = "litellm-service" # OpenWebUI 및 Prometheus에서 접근할 서비스 이름
    namespace = kubernetes_namespace.app_namespace.metadata[0].name # 네임스페이스 참조
  }
  spec {
    selector = {
      app = kubernetes_deployment.litellm_deployment.spec[0].selector[0].match_labels.app # .selector 뒤에 [0] 추가
    }
    port {
      name = "api"
      protocol    = "TCP"
      port        = var.litellm_api_port
      target_port = var.litellm_api_port
      # 로컬 NodePort 는 AWS 에서 사용 안함
      # node_port = var.litellm_service_nodeport
    }
    port {
      name = "metrics" # Prometheus 스크래핑을 위한 포트
      protocol    = "TCP"
      port        = var.litellm_metrics_port
      target_port = var.litellm_metrics_port
    }
    type = "ClusterIP" # 클러스터 내부 접근용
  }
  depends_on = [ kubernetes_deployment.litellm_deployment ]
}

# OpenWebUI Service (Version 1) - ClusterIP: Ingress에서 접근
# A/B 테스트를 위해 v1 Pod 만 선택하는 별도의 서비스 생성
resource "kubernetes_service" "openwebui_v1_service" {
  metadata {
    name      = "openwebui-v1-service" # v1 Pod 만 바라보는 서비스 이름
    namespace = kubernetes_namespace.app_namespace.metadata[0].name # 네임스페이스 참조
  }
  spec {
    selector = {
      app     = "openwebui"
      version = "v1" # v1 라벨을 가진 Pod 만 선택
    }
    port {
      protocol    = "TCP"
      port        = 80 # Ingress 에서 바라볼 포트 (Target Group 의 포트)
      target_port = var.openwebui_port # OpenWebUI 컨테이너 실제 포트 (8080)
    }
    type = "ClusterIP" # Ingress 가 내부에서 접근하므로 ClusterIP 사용
  }
  depends_on = [ kubernetes_deployment.openwebui_deployment_v1 ]
}

# OpenWebUI Service (Version 2) - ClusterIP: Ingress에서 접근
# A/B 테스트를 위해 v2 Pod 만 선택하는 별도의 서비스 생성
resource "kubernetes_service" "openwebui_v2_service" {
  metadata {
    name      = "openwebui-v2-service" # v2 Pod 만 바라보는 서비스 이름
    namespace = kubernetes_namespace.app_namespace.metadata[0].name # 네임스페이스 참조
  }
  spec {
    selector = {
      app     = "openwebui"
      version = "v2" # v2 라벨을 가진 Pod 만 선택
    }
    port {
      protocol    = "TCP"
      port        = 80 # Ingress 에서 바라볼 포트
      target_port = var.openwebui_port # OpenWebUI 컨테이너 실제 포트 (8080)
    }
    type = "ClusterIP" # Ingress 가 내부에서 접근하므로 ClusterIP 사용
  }
  depends_on = [ kubernetes_deployment.openwebui_deployment_v2 ]
}

# Prometheus Service (LoadBalancer: 외부 접근용 - UI)
# Prometheus UI 에 직접 외부에서 접근하기 위해 LoadBalancer 사용
# Ingress 를 사용하는 것이 더 일반적이지만, 여기서는 LoadBalancer Service Type 으로 직접 노출
resource "kubernetes_service" "prometheus_service" {
  metadata {
    name      = "prometheus-service" # 외부에서 접근할 서비스 이름 (AWS ALB/NLB 생성됨)
    namespace = kubernetes_namespace.app_namespace.metadata[0].name # 네임스페이스 참조
    annotations = {
      # Load Balancer 타입을 지정 (기본은 Classic ELB, ALB/NLB 사용 시 명시)
      "service.beta.kubernetes.io/aws-load-balancer-type" = "nlb" # Network Load Balancer 사용 (일반적)
      # "service.beta.kubernetes.io/aws-load-balancer-scheme" = "internet-facing" # 외부용 (기본값)
      # "service.beta.kubernetes.io/aws-load-balancer-ssl-cert" = "arn:aws:acm:..." # HTTPS 리스너 설정 시 ACM 인증서 ARN 지정
      # "service.beta.kubernetes.io/aws-load-balancer-backend-protocol" = "tcp" # Backend 프로토콜 (기본 tcp)
      # "service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled" = "true" # Cross-zone 활성화 (권장)
    }
  }
  spec {
    selector = {
      app = kubernetes_deployment.prometheus_deployment.spec[0].selector[0].match_labels.app # .selector 뒤에 [0] 추가
    }
    port {
      protocol    = "TCP"
      port        = 80 # Load Balancer 리스너 포트 (일반적으로 80 또는 443)
      target_port = var.prometheus_port # Prometheus 컨테이너 실제 포트 (9090)
    }
    type = "LoadBalancer" # AWS NLB 자동 프로비저닝
  }
  depends_on = [ kubernetes_deployment.prometheus_deployment ]
}


# --- ALB Ingress Controller 배포 (Helm 사용) ---
# AWS Load Balancer Controller 를 EKS 클러스터에 배포합니다.
# 이 컨트롤러가 Ingress 리소스를 감지하여 AWS ALB 를 생성 및 관리합니다.
# IRSA (IAM Roles for Service Accounts) 설정이 선행되어야 합니다.
# (IRSA 설정 가이드: https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts-rbac.html)
# (LBC IRSA 설정 가이드: https://docs.aws.amazon.com/eks/latest/userguide/lbc-iam.html)
# (LBC Helm 차트 설치 가이드: https://docs.aws.amazon.com/eks/latest/userguide/lbc-helm.html)
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.6.2" # EKS K8s 버전에 맞는 최신 버전 확인 필요 (https://github.com/aws/eks-charts/blob/main/stable/aws-load-balancer-controller/Chart.yaml)
  namespace  = "kube-system" # 보통 kube-system 네임스페이스에 설치

  # Values for the Helm chart
  values = [
    jsonencode({
      clusterName = aws_eks_cluster.main.name # 생성된 EKS 클러스터 이름 설정
      serviceAccount = {
        # create = true # ServiceAccount 자동 생성 시 true
        # name = "aws-load-balancer-controller" # 생성될 ServiceAccount 이름
        # IRSA 설정 (ServiceAccount 와 IAM 역할 연결)
        annotations = {
          "eks.amazonaws.com/role-arn" = "arn:aws:iam::ACCOUNT_ID:role/YOUR_LBC_IAM_ROLE_ARN" # LBC에 연결할 IAM Role ARN (미리 생성해야 함)
        }
      }
      # image.repository, image.tag 등으로 이미지 변경 가능
    })
  ]

  # EKS 클러스터 및 Helm Provider 준비 완료 후 배포
  depends_on = [
    aws_eks_node_group.main, # 노드 그룹이 Ready 상태가 되어야 Pod가 스케줄링 됨
    provider.helm,
    # kubernetes_namespace.kube_system # kube-system 네임스페이스가 없다면 생성 필요
  ]
}


# --- OpenWebUI Ingress (A/B Testing 구현) ---
# AWS ALB 를 프로비저닝하고 OpenWebUI v1/v2 서비스로 트래픽을 라우팅하는 Ingress 규칙 정의
resource "kubernetes_ingress_v1" "openwebui_ingress" {
  metadata {
    name      = "openwebui-ingress"
    namespace = kubernetes_namespace.app_namespace.metadata[0].name # 네임스페이스 참조
    annotations = {
      # ALB Ingress Controller 사용을 명시
      # 최신 버전 (1.x) 은 ingress.k8s.aws/class: alb 사용 권장
      "kubernetes.io/ingress.class" = "alb" # 또는 "ingress.k8s.aws/class" = "alb"
      # ALB 스키마 (internet-facing or internal)
      "alb.ingress.kubernetes.io/scheme" = "internet-facing" # 외부 접근용
      # HTTPS 설정 (선택 사항 - ACM 인증서 필요)
      # "alb.ingress.kubernetes.io/listen-ports" = "[{"HTTP": 80}, {"HTTPS": 443}]"
      # "alb.ingress.kubernetes.io/ssl-redirect" = "443" # HTTP 로 오면 HTTPS 로 리다이렉트
      # "alb.ingress.kubernetes.io/certificate-arn" = "arn:aws:acm:..." # ACM 인증서 ARN 지정

      # ALB Target Group 등록 방식 (instance or ip) - Fargate 사용 시 ip 필수
      # IP 모드는 Pod IP 로 바로 트래픽 전달 (권장)
      "alb.ingress.kubernetes.io/target-type" = "ip"

      # ALB Security Group 설정 (선택 사항, 미지정시 컨트롤러가 생성)
      # "alb.ingress.kubernetes.io/security-groups" = "sg-xxxx"

      # --- A/B 테스트를 위한 Weighted Routing Annotation ---
      # 특정 경로 ("/") 에 대한 트래픽을 여러 액션으로 분배하도록 설정
      # 액션 이름은 "actions.<action-name>" 형식으로 annotation key 에서 참조
      # default-backend 는 사용하지 않고 actions 에서 정의한 액션들을 사용
      "alb.ingress.kubernetes.io/actions.openwebui-weighted" = jsonencode({
        type = "forward" # 트래픽을 Service 로 전달
        forward_config = {
          target_groups = [
            {
              # 첫 번째 대상 그룹: OpenWebUI v1 서비스
              serviceName = kubernetes_service.openwebui_v1_service.metadata[0].name
              servicePort = 80 # Ingress 에서 바라보는 서비스 포트 (openwebui-v1-service 의 target_port 가 80 이면 80, 아니면 해당 포트)
              weight      = var.openwebui_v1_weight # variables.tf 에서 정의한 v1 가중치 (0-100)
            },
            {
              # 두 번째 대상 그룹: OpenWebUI v2 서비스
              serviceName = kubernetes_service.openwebui_v2_service.metadata[0].name
              servicePort = 80 # Ingress 에서 바라보는 서비스 포트 (openwebui-v2-service 의 target_port 가 80 이면 80, 아니면 해당 포트)
              weight      = var.openwebui_v2_weight # variables.tf 에서 정의한 v2 가중치 (0-100)
            }
          ]
        }
      })
      # --- Weighted Routing Annotation 끝 ---

      # 추가적인 ALB 설정 (예: idle timeout)
      # "alb.ingress.kubernetes.io/load-balancer-attributes" = "idle_timeout.timeout_seconds=600"
    }
  }

  # Ingress 규칙 정의
  spec {
    # default_backend 는 Weighted Routing 시 사용하지 않습니다.
    # default_backend {
    #   service {
    #     name = kubernetes_service.openwebui_v1_service.metadata[0].name # 기본 서비스 (fallback 등)
    #     port { number = 80 }
    #   }
    # }

    # Path 기반 라우팅 규칙
    rule {
      # host = "your.custom.domain.com" # 커스텀 도메인 사용 시 주석 해제
      http {
        path {
          path = "/" # 모든 경로 요청
          path_type = "Prefix" # 접두사 일치

          # Weighted Routing 을 적용할 액션 지정
          backend {
            service { # Service 블록은 명목상 필요, 실제 라우팅은 action 에서 정의
              name = kubernetes_service.openwebui_v1_service.metadata[0].name # 아무 서비스나 참조 (실제 사용 안됨)
              port { number = 80 } # 아무 포트나 참조 (실제 사용 안됨)
            }
            # Weighted Routing 액션을 사용하도록 지정 (어노테이션의 액션 이름과 일치)
            resource {
              api_group = "networking.k8s.io"
              kind      = "Ingress" # 이 필드는 Ingress 정의 자체를 참조할 때 사용... 대신 service.name 으로 변경
              # --- 이 부분을 위 annotation의 액션 이름으로 변경 ---
              # name 필드를 사용
              name = "openwebui-weighted" # annotation key 에서 정의한 액션 이름 ("actions.openwebui-weighted")
              # --- 변경 완료 ---
            }
          }
        }
        # 다른 Path 규칙 추가 가능 (예: /admin -> admin-service)
        /*
        path {
          path = "/admin"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.admin_service.metadata[0].name
              port { number = 80 }
            }
          }
        }
        */
      }
    }
  }

  # 네임스페이스 및 관련 서비스들 생성 완료 후 Ingress 생성
  depends_on = [
    kubernetes_namespace.app_namespace,
    kubernetes_service.openwebui_v1_service, # 대상 서비스가 먼저 생성되어야 함
    kubernetes_service.openwebui_v2_service, # 대상 서비스가 먼저 생성되어야 함
    helm_release.aws_load_balancer_controller, # LBC 컨트롤러가 배포되어 있어야 Ingress 를 감지하고 ALB 생성
  ]
}