# variables.tf (AWS 관련 추가 변수)

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "ap-northeast-2" # 서울 리전
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "llm-project-eks"
}

variable "vpc_id" {
  description = "ID of the VPC where the EKS cluster will be deployed"
  type        = string
  default = "vpc-0f11e0b7cb225055a" # TODO: 실제 VPC ID로 변경 필요
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for EKS worker nodes"
  type        = list(string)
  default = ["subnet-020d530cbcaed0656", "subnet-06bed7cfb33b120c1"] # TODO: 실제 Subnet ID로 변경 필요
}

variable "instance_type" {
  description = "EC2 instance type for EKS worker nodes"
  type        = string
  default     = "t3.medium" # EKS 노드에 적합한 인스턴스 타입 선택
}

variable "node_group_desired_capacity" {
  description = "Desired number of worker nodes in the EKS node group"
  type        = number
  default     = 2
}

variable "node_group_min_capacity" {
  description = "Minimum number of worker nodes in the EKS node group"
  type        = number
  default     = 1
}

variable "node_group_max_capacity" {
  description = "Maximum number of worker nodes in the EKS node group"
  type        = number
  default     = 3
}

variable "namespace" {
  description = "Kubernetes namespace for all resources"
  type        = string
  default     = "default"
}

variable "litellm_api_port" {
  description = "API port for LiteLLM"
  type        = number
  default     = 4000
}

variable "litellm_metrics_port" {
  description = "Metrics port for LiteLLM"
  type        = number
  default     = 8000
}

variable "openwebui_port" {
  description = "Service port for OpenWebUI"
  type        = number
  default     = 3000
}

variable "prometheus_port" {
  description = "Service port for Prometheus"
  type        = number
  default     = 9090
}

variable "grafana_port" {
  description = "Service port for Grafana"
  type        = number
  default     = 3001
}


variable "postgres_user" {
  description = "PostgreSQL username"
  type        = string
}

variable "postgres_password" {
  description = "PostgreSQL password"
  type        = string
}

variable "postgres_db" {
  description = "PostgreSQL database name"
  type        = string
}

variable "DATABASE_URL" {
  description = "Full PostgreSQL connection string"
  type        = string
}

variable "GEMINI_API_KEY" {
  description = "Gemini API key for LiteLLM"
  type        = string
}

variable "AZURE_API_KEY" {
  description = "Azure OpenAI API key"
  type        = string
}

variable "AZURE_API_BASE" {
  description = "Azure OpenAI base endpoint"
  type        = string
}

variable "AZURE_API_VERSION" {
  description = "Azure OpenAI API version"
  type        = string
}

variable "LITELLM_MASTER_KEY" {
  description = "Master API key for LiteLLM"
  type        = string
}

variable "LITELLM_SALT_KEY" {
  description = "Salt key for LiteLLM"
  type        = string
}

# 기존 NodePort 변수는 이제 LoadBalancer 타입을 사용할 것이므로 사실상 사용되지 않지만,
# 코드를 유연하게 유지하려면 남겨두거나, LoadBalancer 서비스의 특정 포트 매핑을 명시적으로 관리할 수 있습니다.
# 여기서는 NodePort 변수를 그대로 유지하면서 LoadBalancer로 전환합니다.
# AWS LoadBalancer는 기본적으로 Service Port를 외부에 노출합니다.