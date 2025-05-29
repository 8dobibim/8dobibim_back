# main.tf (부분 수정 및 추가)

# AWS Provider 설정
provider "aws" {
  region = var.aws_region # variables.tf에 정의된 AWS 리전 사용
}

# EKS Cluster 생성
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [aws_security_group.eks_cluster_sg.id]
    endpoint_private_access = true
    endpoint_public_access  = true # 필요에 따라 public access 제한 가능
  }

  kubernetes_network_config {
    service_ipv4_cidr = "172.20.0.0/16" # EKS 기본 서비스 CIDR
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
  ]
}

# EKS Node Group 생성
resource "aws_eks_node_group" "nodes" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-nodes"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = var.private_subnet_ids
  instance_types  = [var.instance_type] # t3.medium 또는 t3.large 등으로 변경
  desired_size    = var.node_group_desired_capacity
  min_size        = var.node_group_min_capacity
  max_size        = var.node_group_max_capacity

  scaling_config {
    desired_size = var.node_group_desired_capacity
    min_size     = var.node_group_min_capacity
    max_size     = var.node_group_max_capacity
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_container_registry_policy,
  ]
}

# Kubernetes Provider 설정 (EKS 클러스터에 연결)
provider "kubernetes" {
  host                   = aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.main.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.main.token
}

# EKS Cluster Auth Data Source
data "aws_eks_cluster_auth" "main" {
  name = aws_eks_cluster.main.name
}

# EKS Cluster IAM Role
resource "aws_iam_role" "eks_cluster_role" {
  name = "${var.cluster_name}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

# EKS Node IAM Role
resource "aws_iam_role" "eks_node_role" {
  name = "${var.cluster_name}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      },
    ]
  })
}

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

# Security Group for EKS Cluster
resource "aws_security_group" "eks_cluster_sg" {
  name        = "${var.cluster_name}-sg"
  description = "Security group for EKS cluster"
  vpc_id      = var.vpc_id # variables.tf에 정의된 VPC ID 사용

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.38.0.0/16"] # TODO: 실제 환경에서는 특정 IP로 제한
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# PersistentVolumeClaim (EKS 환경에 맞게 StorageClass 설정 필요)
# AWS EBS CSI Driver를 설치했다면, StorageClass를 정의하여 동적 프로비저닝 가능
resource "kubernetes_persistent_volume_claim" "postgres_pvc" {
  metadata {
    name      = "postgres-pvc"
    namespace = var.namespace
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "5Gi"
      }
    }
    storage_class_name = "gp2" # 또는 "gp3" 등 AWS EBS StorageClass 이름
  }
}

# --- Service Definitions (NodePort -> LoadBalancer) ---

# LiteLLM Service (ClusterIP -> LoadBalancer)
resource "kubernetes_service" "litellm_service" {
  metadata {
    name      = "litellm-service"
    namespace = var.namespace
    annotations = {
      # AWS Load Balancer Controller를 사용한다면 Ingress Resource를 사용하는 것이 더 권장됩니다.
      # 여기서는 Service Type: LoadBalancer로 직접 생성하는 예시입니다.
      "service.beta.kubernetes.io/aws-load-balancer-type" = "nlb" # 또는 "elb"
      "service.beta.kubernetes.io/aws-load-balancer-scheme" = "internet-facing" # 또는 "internal"
      # "service.beta.kubernetes.io/aws-load-balancer-healthcheck-path" = "/health" # 헬스 체크 경로
    }
  }
  spec {
    selector = {
      app = kubernetes_deployment.litellm_deployment.spec[0].selector[0].match_labels.app
    }
    port {
      name        = "api"
      protocol    = "TCP"
      port        = var.litellm_api_port
      target_port = var.litellm_api_port
    }
    port {
      name        = "metrics" # Prometheus 스크래핑을 위한 포트
      protocol    = "TCP"
      port        = var.litellm_metrics_port
      target_port = var.litellm_metrics_port
    }
    type = "LoadBalancer" # AWS 환경에서는 LoadBalancer로 변경
  }
}

# OpenWebUI Service (NodePort -> LoadBalancer)
resource "kubernetes_service" "openwebui_service" {
  metadata {
    name      = "openwebui-service"
    namespace = var.namespace
    annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-type" = "nlb"
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
    type = "LoadBalancer" # AWS 환경에서는 LoadBalancer로 변경
  }
}

# Prometheus Service (NodePort -> LoadBalancer)
resource "kubernetes_service" "prometheus_service" {
  metadata {
    name      = "prometheus-service"
    namespace = var.namespace
    annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-type" = "nlb"
      "service.beta.kubernetes.io/aws-load-balancer-scheme" = "internet-facing"
    }
  }
  spec {
    selector = {
      app = kubernetes_deployment.prometheus_deployment.spec[0].selector[0].match_labels.app
    }
    port {
      protocol    = "TCP"
      port        = var.prometheus_port
      target_port = var.prometheus_port
    }
    type = "LoadBalancer" # AWS 환경에서는 LoadBalancer로 변경
  }
}

# Grafana Service (NodePort -> LoadBalancer)
resource "kubernetes_service" "grafana_service" {
  metadata {
    name      = "grafana-service"
    namespace = var.namespace
    annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-type" = "nlb"
      "service.beta.kubernetes.io/aws-load-balancer-scheme" = "internet-facing"
    }
  }
  spec {
    selector = {
      app = kubernetes_deployment.grafana_deployment.spec[0].selector[0].match_labels.app
    }
    port {
      protocol    = "TCP"
      port        = var.grafana_port
      target_port = var.grafana_port
    }
    type = "LoadBalancer" # AWS 환경에서는 LoadBalancer로 변경
  }
}

# 나머지 Deployment 및 ConfigMap, Secret 등은 이전 main.tf에서 거의 동일하게 유지됩니다.
# PostgreSQL Deployment, LiteLLM Deployment, OpenWebUI Deployment (v1), Prometheus Deployment, Grafana Deployment
# app_secrets, litellm_config, prometheus_config, grafana_datasources ConfigMap 등
# 이들은 Kubernetes Deployment/Service의 정의이므로 EKS 클러스터가 생성되면 그 위에 배포됩니다.