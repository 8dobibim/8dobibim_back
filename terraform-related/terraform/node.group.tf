# terraform-related/terraform/node.group.tf

# 기존 data "aws_iam_role" 블록 삭제하고 아래 코드로 대체
resource "aws_iam_role" "eks_node_role" {
  name = "eks-node-role-${var.cluster_name}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# 노드 역할에 필요한 정책 연결
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "ecr_read_only" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_role.name
}

# 기존 aws_eks_node_group 리소스를 수정하여 새로 생성한 역할 사용
resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = var.eks_node_group_name
  node_role_arn   = aws_iam_role.eks_node_role.arn  # 여기가 수정됨: data 참조에서 resource 참조로
  subnet_ids      = var.eks_subnet_ids

  scaling_config {
    desired_size = var.eks_desired_capacity
    max_size     = var.eks_max_size
    min_size     = var.eks_min_size
  }

  instance_types = [var.eks_node_instance_type]
  
  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.ecr_read_only
  ]
}