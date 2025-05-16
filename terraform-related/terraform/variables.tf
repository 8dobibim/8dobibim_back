#terraform-related/terraform/variables.tf
# AWS 리전 설정 (기본값: 서울 리전)
variable "aws_region" {
  type        = string
  default     = "ap-northeast-2"
}

# EKS 클러스터 이름
variable "cluster_name" {
  type        = string
  description = "EKS 클러스터 이름"
}

# EKS 노드 그룹 이름
variable "eks_node_group_name" {
  type = string
}

# EC2 인스턴스 타입 (예: t3.medium)
variable "eks_node_instance_type" {
  type = string
}

# 오토스케일링: 원하는 파드 수
variable "eks_desired_capacity" {
  type = number
}

# 오토스케일링: 최소 파드 수
variable "eks_min_size" {
  type = number
}

# 오토스케일링: 최대 파드 수
variable "eks_max_size" {
  type = number
}

# 사용할 VPC ID (EKS 클러스터가 배치될 VPC)
variable "eks_vpc_id" {
  type = string
}

# 사용할 서브넷 목록 (EKS 노드 및 컨트롤 플레인용)
variable "eks_subnet_ids" {
  type = list(string)
}



# eks_cluster_name이 위 cluster_name과 중복될 경우도 있으므로 따로 사용 가능
variable "eks_cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "openwebui"
}


# API 키 관련 변수들
variable "gemini_api_key" {
  description = "Gemini API Key"
  type        = string
  sensitive   = true
}

variable "azure_api_key" {
  description = "Azure OpenAI API Key"
  type        = string
  sensitive   = true
}

variable "azure_api_base" {
  description = "Azure OpenAI API Base URL"
  type        = string
}

variable "azure_api_version" {
  description = "Azure OpenAI API Version"
  type        = string
  default     = "2024-02-15-preview"
}

# 데이터베이스 관련 변수들
variable "postgres_db" {
  description = "PostgreSQL Database Name"
  type        = string
  default     = "litellm_db"
}

variable "postgres_user" {
  description = "PostgreSQL Username"
  type        = string
  default     = "litellm_user"
}

variable "postgres_password" {
  description = "PostgreSQL Password"
  type        = string
  sensitive   = true
}

variable "database_url" {
  description = "Full PostgreSQL Connection URL"
  type        = string
  sensitive   = true
  default     = "postgresql://litellm_user:4321@postgres:5432/litellm_db"
}

# LiteLLM 관련 변수들
variable "litellm_master_key" {
  description = "LiteLLM Master Key"
  type        = string
  sensitive   = true
}

variable "litellm_salt_key" {
  description = "LiteLLM Salt Key"
  type        = string
  sensitive   = true
}
