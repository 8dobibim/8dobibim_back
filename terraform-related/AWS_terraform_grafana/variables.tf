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
  # default = "vpc-0abcdef1234567890" # TODO: 실제 VPC ID로 변경 필요
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for EKS worker nodes"
  type        = list(string)
  # default = ["subnet-0abcdef1234567890", "subnet-0fedcba9876543210"] # TODO: 실제 Subnet ID로 변경 필요
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

# 기존 NodePort 변수는 이제 LoadBalancer 타입을 사용할 것이므로 사실상 사용되지 않지만,
# 코드를 유연하게 유지하려면 남겨두거나, LoadBalancer 서비스의 특정 포트 매핑을 명시적으로 관리할 수 있습니다.
# 여기서는 NodePort 변수를 그대로 유지하면서 LoadBalancer로 전환합니다.
# AWS LoadBalancer는 기본적으로 Service Port를 외부에 노출합니다.