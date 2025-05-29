# main.tf (부분 수정 및 추가)

# AWS Provider 설정
provider "aws" {
  region = var.aws_region
}

# EKS Cluster 생성
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

# EKS Node Group 생성
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
  ]
}


# Kubernetes Provider 설정
provider "kubernetes" {
  host                   = aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.main.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.main.token
}

data "aws_eks_cluster_auth" "main" {
  name = aws_eks_cluster.main.name
}

# IAM Roles and Attachments
resource "aws_iam_role" "eks_cluster_role" {
  name = "${var.cluster_name}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "eks.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

resource "aws_iam_role" "eks_node_role" {
  name = "${var.cluster_name}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
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

# Security Group
resource "aws_security_group" "eks_cluster_sg" {
  name        = "${var.cluster_name}-sg"
  description = "Security group for EKS cluster"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.38.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# PVC for PostgreSQL
resource "kubernetes_persistent_volume_claim" "postgres_pvc" {
  metadata {
    name      = "postgres-pvc"
    namespace = var.namespace
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = { storage = "5Gi" }
    }
    storage_class_name = "gp2"
  }
}

# Kubernetes Services
# LiteLLM
resource "kubernetes_service" "litellm_service" {
  metadata {
    name      = "litellm-service"
    namespace = var.namespace
    annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-type"    = "nlb"
      "service.beta.kubernetes.io/aws-load-balancer-scheme"  = "internet-facing"
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

# OpenWebUI
resource "kubernetes_service" "openwebui_service" {
  metadata {
    name      = "openwebui-service"
    namespace = var.namespace
    annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-type"    = "nlb"
      "service.beta.kubernetes.io/aws-load-balancer-scheme"  = "internet-facing"
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

# Prometheus
resource "kubernetes_service" "prometheus_service" {
  metadata {
    name      = "prometheus-service"
    namespace = var.namespace
    annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-type"    = "nlb"
      "service.beta.kubernetes.io/aws-load-balancer-scheme"  = "internet-facing"
    }
  }
  spec {
    selector = {
      app = "prometheus"
    }
    port {
      protocol    = "TCP"
      port        = var.prometheus_port
      target_port = var.prometheus_port
    }
    type = "LoadBalancer"
  }
}

# Grafana
resource "kubernetes_service" "grafana_service" {
  metadata {
    name      = "grafana-service"
    namespace = var.namespace
    annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-type"    = "nlb"
      "service.beta.kubernetes.io/aws-load-balancer-scheme"  = "internet-facing"
    }
  }
  spec {
    selector = {
      app = "grafana"
    }
    port {
      protocol    = "TCP"
      port        = var.grafana_port
      target_port = var.grafana_port
    }
    type = "LoadBalancer"
  }
}


resource "kubernetes_deployment" "litellm_deployment" {
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
            container_port = var.litellm_api_port
          }
          port {
            container_port = var.litellm_metrics_port
          }
        }
      }
    }
  }
}

resource "kubernetes_deployment" "openwebui_deployment" {
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

          env {
            name  = "DATABASE_URL"
            value = var.database_url
          }
          env {
            name  = "LITELLM_PROXY_BASE_URL"
            value = "http://litellm-service:${var.litellm_api_port}"
          }

          port {
            container_port = var.openwebui_port
          }
        }
      }
    }
  }
}

resource "kubernetes_deployment" "prometheus_deployment" {
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
            container_port = var.prometheus_port
          }
        }
      }
    }
  }
}

resource "kubernetes_deployment" "grafana_deployment" {
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
            container_port = var.grafana_port
          }
        }
      }
    }
  }
}
