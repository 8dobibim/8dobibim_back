#terraform-related/terraform/terraform.tfvars

cluster_name = "openwebui"

eks_cluster_name   = "openwebui" # 클러스터 이름
eks_node_group_name = "openwebui-nodegroup" # 노드 그룹 이름
eks_node_instance_type = "t3.large" # 워커 노드 EC2 타입
eks_desired_capacity = 2
eks_min_size         = 1
eks_max_size         = 3
eks_subnet_ids       = ["subnet-086b68e382a3ec6bb", "subnet-0a64aec9c34f85292"] # 퍼블릭/프라이빗 서브넷 ID들
eks_vpc_id           = "vpc-078d1731a5bb8c6b0" # 클러스터가 들어갈 VPC ID

