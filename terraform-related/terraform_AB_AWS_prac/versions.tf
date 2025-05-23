# versions.tf
terraform {
  required_version = ">= 1.0"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    aws = { # AWS Provider 추가
      source  = "hashicorp/aws"
      version = "~> 5.0" # 사용하는 AWS Provider 버전에 맞게 수정
    }
    helm = { # Helm Provider 추가
      source  = "hashicorp/helm"
      version = "~> 2.0" # 사용하는 Helm Provider 버전에 맞게 수정
    }
  }
}