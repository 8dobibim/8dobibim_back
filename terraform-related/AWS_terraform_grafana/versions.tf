# versions.tf

terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.23.0" # 최신 안정 버전으로 업데이트할 수 있습니다.
    }
    aws = {
      source  = "hashicorp/aws"
      version = "5.45.0" # 최신 안정 버전으로 업데이트할 수 있습니다.
    }
    # EKS 클러스터 관리에 필요한 additional providers (선택 사항)
    # 예를 들어, aws-auth configmap을 관리하려면 helm 또는 null provider가 필요할 수 있습니다.
    # helm = {
    #   source  = "hashicorp/helm"
    #   version = "2.11.0"
    # }
  }
}