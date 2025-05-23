#terraform-related/terraform/main.tf
# Terraform 설정 블록: 사용할 프로바이더 정의
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"      # AWS 프로바이더 사용
      version = "~> 4.0"             # 4.x 버전대를 사용 
    }
  }
}

# AWS 프로바이더 설정
provider "aws" {
  region  = var.aws_region  # 사용할 리전은 변수로부터 입력 받음
  
}

# 이미 존재하는 IAM Role을 참조하는 data 블록은 삭제하고 아래 코드로 대체
resource "aws_iam_role" "eks_cluster_role" {
  name = "eks-cluster-role-${var.cluster_name}"
  
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
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

# EKS 클러스터 생성 리소스 (기존 코드를 수정)
resource "aws_eks_cluster" "this" {
  name     = var.cluster_name  # 클러스터 이름은 변수에서 받아옴
  role_arn = aws_iam_role.eks_cluster_role.arn  # 여기를 수정: data 참조에서 resource 참조로
  version  = "1.29"  # 사용할 Kubernetes 버전

  vpc_config {
    subnet_ids = var.eks_subnet_ids  # EKS 클러스터가 사용할 서브넷 목록
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy  # 의존성 추가
  ]
}

provider "kubernetes" {
  host                   = aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.this.certificate_authority[0].data)
  
  # AWS EKS 토큰을 사용한 인증
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.this.name]  
    command     = "aws"
  }
}

# API 키 관련 Secret 생성
resource "kubernetes_secret" "api_credentials" {
  metadata {
    name      = "api-credentials"
    namespace = "default"
  }

  data = {
    "gemini-api-key"     = var.gemini_api_key
    "azure-api-key"      = var.azure_api_key
    "azure-api-base"     = var.azure_api_base
    "azure-api-version"  = var.azure_api_version
    "litellm-master-key" = var.litellm_master_key
    "litellm-salt-key"   = var.litellm_salt_key
  }

  depends_on = [
    aws_eks_cluster.this,
    aws_eks_node_group.this  # 노드가 준비된 후 Secret 생성
  ]
}

# 데이터베이스 관련 Secret 생성
resource "kubernetes_secret" "db_credentials" {
  metadata {
    name      = "db-credentials"
    namespace = "default"
  }

  data = {
    "postgres-db"       = var.postgres_db
    "postgres-user"     = var.postgres_user
    "postgres-password" = var.postgres_password
    "database-url"      = var.database_url
  }

  depends_on = [
    aws_eks_cluster.this,
    aws_eks_node_group.this
  ]
}

# ConfigMap으로 LiteLLM 설정 생성 (민감하지 않은 설정)
resource "kubernetes_config_map" "litellm_config" {
  metadata {
    name      = "litellm-config"
    namespace = "default"
  }

  data = {
    "config.yaml" = <<-EOT
      model_list:
      - model_name: gpt-3.5-turbo
        litellm_params:
          model: azure/gpt-35-turbo-deployment 
          api_base: ${var.azure_api_base}
          api_version: ${var.azure_api_version}
      
      general_settings:
      
      litellm_settings:
        set_verbose: True
    EOT
  }

  depends_on = [
    aws_eks_cluster.this,
    aws_eks_node_group.this
  ]
}

# Prometheus 설정 ConfigMap
resource "kubernetes_config_map" "prometheus_config" {
  metadata {
    name      = "prometheus-config"
    namespace = "default"
  }

  data = {
    "prometheus.yml" = <<-EOT
      global:
        scrape_interval: 15s
        evaluation_interval: 15s
      
      scrape_configs:
        - job_name: 'prometheus'
          static_configs:
            - targets: ['localhost:9090']
        - job_name: 'nginx'
          static_configs:
            - targets: ['nginx-exporter:9113']
    EOT
  }

  depends_on = [
    aws_eks_cluster.this,
    aws_eks_node_group.this
  ]
}