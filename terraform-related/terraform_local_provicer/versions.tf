# versions.tf

terraform {
  required_version = ">= 1.0" # 사용하는 Terraform 버전에 맞게 수정
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0" # 사용하는 Kubernetes Provider 버전에 맞게 수정
    }
  }
}