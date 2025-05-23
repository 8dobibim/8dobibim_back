AWS 전환을 위한 추가 설명 및 고려사항:
VPC 및 Subnet: AWS EKS 클러스터를 배포하려면 기존 VPC와 프라이빗 서브넷이 필요합니다. variables.tf의 vpc_id와 private_subnet_ids를 실제 AWS 환경에 맞는 값으로 변경해야 합니다. 만약 VPC가 없다면, Terraform으로 VPC를 함께 프로비저닝하는 코드를 추가할 수도 있습니다.
IAM Role: EKS 클러스터와 워커 노드가 AWS 리소스에 접근하기 위한 IAM 역할이 필요합니다. 위에 추가된 aws_iam_role 및 aws_iam_role_policy_attachment 리소스가 이를 담당합니다.
Security Group: EKS 클러스터 통신을 위한 보안 그룹도 필요합니다.
Kubernetes Provider 재설정: Terraform은 EKS 클러스터가 완전히 프로비저닝된 후에야 해당 클러스터에 연결할 수 있습니다. 이를 위해 kubernetes 프로바이더 설정에 aws_eks_cluster.main.endpoint, aws_eks_cluster.main.certificate_authority, data.aws_eks_cluster_auth.main.token 값을 동적으로 참조하도록 변경했습니다.
Service Type: 로컬에서 사용하던 NodePort 서비스는 AWS 환경에서는 LoadBalancer 타입으로 변경하여 AWS ELB(Elastic Load Balancer)를 통해 외부에서 접근할 수 있도록 합니다. service.beta.kubernetes.io/aws-load-balancer-type 어노테이션을 사용하여 NLB (Network Load Balancer) 또는 ELB (Classic Load Balancer) 타입을 선택할 수 있습니다. 보통은 NLB가 더 권장됩니다.
PersistentVolumeClaim (PVC): postgres_pvc와 같은 PVC는 로컬 환경의 hostpath 대신 AWS EBS와 같은 클라우드 스토리지 솔루션을 사용하도록 storage_class_name을 설정해야 합니다. EKS 클러스터에 EBS CSI Driver가 설치되어 있어야 합니다.
kubeconfig: config_path = "C:\\Users\\Woo\\.kube\\config" 부분은 로컬 테스트를 위한 경로였지만, EKS를 배포한 후에는 Terraform이 자동으로 EKS 클러스터에 연결하기 위해 host, cluster_ca_certificate, token을 사용합니다. 따라서 이 부분은 EKS 배포 시 더 이상 로컬 kubeconfig 파일을 직접 사용하지 않도록 자동으로 설정됩니다.
AWS 배포 절차:
AWS 자격 증명 설정: Terraform이 AWS에 접근할 수 있도록 AWS CLI를 통해 자격 증명을 설정하거나 환경 변수를 설정해야 합니다.
VPC 및 Subnet 준비: EKS 클러스터를 배포할 VPC와 프라이빗 서브넷을 미리 준비하거나, Terraform으로 함께 생성하는 코드를 추가해야 합니다.
파일 업데이트: 위에서 제공된 versions.tf 파일을 생성하고, main.tf와 variables.tf를 업데이트합니다. 특히 variables.tf의 AWS 관련 변수들(vpc_id, private_subnet_ids 등)을 실제 값으로 채워야 합니다.
terraform init: versions.tf가 추가되고 새 프로바이더가 정의되었으므로 다시 terraform init를 실행하여 필요한 프로바이더를 다운로드합니다.
terraform plan: 변경될 내용을 확인합니다. EKS 클러스터, 노드 그룹, IAM 역할, 보안 그룹 및 서비스 타입 변경 등이 포함될 것입니다.
terraform apply: 모든 것이 올바른지 확인한 후 terraform apply를 실행하여 AWS EKS 환경에 리소스를 프로비저닝합니다. 이 과정은 시간이 오래 걸릴 수 있습니다.
