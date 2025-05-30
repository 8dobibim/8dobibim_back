## Terraform 변수 및 파라미터 설정 가이드

본 Code는 인프라를 위한 세팅은 되어있지만, 실제 서비스 활용에 필요한 API key나 master-password와 관련된 내용은 포함되어 있지 않습니다.

때문에, 실제 apply 직전 **tfvars.example** 파일을 참고하여 개인화된 데이터를 포함한 **terraform.tfvars 파일**을 **로컬에서 설정**하시거나 **AWS 상에 추가하는 과정이 필요**합니다.   

여기서는 제공된 `variables.tf` 파일의 내용을 바탕으로 `terraform.tfvars`에 들어가야 하는 내용을 설명해드리겠습니다.

### 1. `variables.tf` 파일 이해하기

`variables.tf` 파일은 Terraform 프로젝트에서 사용할 모든 변수를 정의하는 곳입니다. 각 변수는 `variable` 블록으로 선언되며, 다음과 같은 속성을 가질 수 있습니다.

* **`description`**: 변수의 목적을 설명합니다. 명확하고 자세하게 작성하여 다른 사람이 코드를 이해하는 데 도움을 줍니다.
* **`type`**: 변수가 어떤 종류의 값(예: `string`, `number`, `bool`, `list`, `map`)을 받을지 정의합니다.
* **`default`**: 변수에 명시적인 값이 제공되지 않을 경우 사용될 기본값을 지정합니다. 개발 환경 등에서 빠르게 테스트할 때 유용합니다.
* **`sensitive`**: `true`로 설정하면 이 변수에 할당된 값이 Terraform 플랜 또는 출력에 표시되지 않도록 숨겨줍니다. **API 키, 비밀번호 등 민감한 정보에 반드시 사용해야 합니다.**

**예시 (`variables.tf` 일부):**

```terraform
variable "namespace" {
  description = "Kubernetes namespace to deploy resources into"
  type        = string
  default     = "llm-project" # 기본 네임스페이스
}

variable "LITELLM_MASTER_KEY" {
  description = "LiteLLM Master Key for authentication/validation"
  type        = string
  sensitive   = true # 민감 정보로 마킹
}
```

---

### 2. `terraform.tfvars` 파일을 통한 변수 값 지정

`variables.tf`에서 변수를 선언했다면, 실제로 Terraform을 실행할 때 이 변수들에 값을 할당해야 합니다. `tfvars` 파일은 변수 값을 저장하는 가장 일반적인 방법입니다.

프로젝트 루트에 `terraform.tfvars`라는 파일이 있다면, Terraform은 자동으로 이 파일을 로드합니다. 또는 `terraform apply -var-file="example.tfvars"`와 같이 특정 `.tfvars` 파일을 지정할 수도 있습니다.

```terraform
# --- 네임스페이스 설정 ---
namespace = "my-llm-staging" # 개발 환경이 아닌 경우 변경

# --- Docker 이미지 버전 설정 ---
litellm_image      = "ghcr.io/berriai/litellm:main-latest"
openwebui_image_v1 = "ghcr.io/open-webui/open-webui:v0.6.7"
openwebui_image_v2 = "ghcr.io/open-webui/open-webui:v0.6.6"
prometheus_image   = "prom/prometheus:v2.47.1"
postgres_image     = "postgres:13"

# --- 애플리케이션 포트 설정 ---
litellm_api_port    = 4000
litellm_metrics_port = 9000
openwebui_port      = 8080
prometheus_port     = 9090
postgres_port       = 5432

# --- 민감한 환경 변수 및 자격 증명 (매우 중요: 실제 값으로 대체) ---
# 이 값들은 절대로 Git 저장소에 직접 커밋해서는 안 됩니다!
# 대신 `terraform apply -var="VAR_NAME=VALUE"` 또는 CI/CD 파이프라인의 시크릿 관리 기능을 사용하세요.
# LiteLLM 인증을 위한 마스터 키 (반드시 변경)
LITELLM_MASTER_KEY  = "YOUR_ACTUAL_LITELLM_MASTER_KEY"
# LiteLLM 인증을 위한 SALT 키 (반드시 변경)
LITELLM_SALT_KEY    = "YOUR_ACTUAL_LITELLM_SALT_KEY"
# Google Gemini API 키 (반드시 변경)
GEMINI_API_KEY      = "YOUR_ACTUAL_GEMINI_API_KEY"
# Azure OpenAI API 키 (반드시 변경)
AZURE_API_KEY       = "YOUR_ACTUAL_AZURE_API_KEY"
# Azure OpenAI API Base URL (예: https://YOUR_RESOURCE_NAME.openai.azure.com/)
AZURE_API_BASE      = "https://your-azure-resource.openai.azure.com/"
# Azure OpenAI API 버전
AZURE_API_VERSION   = "2023-07-01-preview"

# PostgreSQL 데이터베이스 사용자명 (반드시 변경)
postgres_user = "your_actual_postgres_user"
# PostgreSQL 데이터베이스 비밀번호 (반드시 변경)
postgres_password = "your_actual_postgres_password"
# PostgreSQL 데이터베이스 이름 (반드시 변경)
postgres_db = "your_actual_postgres_db_name"
# PostgreSQL 데이터베이스 URL (예: postgresql://user:password@host:port/db)
DATABASE_URL = "postgresql://your_actual_postgres_user:your_actual_postgres_password@postgres-service:5432/your_actual_postgres_db_name"

# --- AWS 리전 및 프로젝트 설정 ---
# AWS 리소스가 배포될 리전 (예: ap-northeast-2는 서울)
aws_region   = "ap-northeast-2"
# 프로젝트 이름 (리소스 태그 및 명명에 사용)
project_name = "llm-project"
# 모든 AWS 리소스에 적용할 기본 태그
aws_tags = {
  Project     = "LLM Inhouse"
  Environment = "Dev" # 배포 환경에 따라 변경 (Dev, Staging, Prod 등)
  ManagedBy   = "Terraform"
}

# --- VPC 네트워크 설정 ---
vpc_cidr             = "10.0.0.0/16"
public_subnets_cidr  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnets_cidr = ["10.0.101.0/24", "10.0.102.0/24"]

# --- EKS 클러스터 설정 ---
eks_cluster_version          = "1.28"
eks_node_group_instance_type = "t3.medium"
eks_node_group_desired_size  = 2
eks_node_group_max_size      = 3
eks_node_group_min_size      = 1

# --- OpenWebUI A/B 테스트 트래픽 분배 설정 ---
openwebui_v1_weight = 70 # v1에 70% 트래픽
openwebui_v2_weight = 30 # v2에 30% 트래픽
# 참고: v1_weight + v2_weight는 일반적으로 100이 되어야 합니다.
```

---

### 번외. `main.tf`에서의 변수 활용

만약, 규정된 변수 외 다른 변수를 활용하거나 설정을 추가하고 싶으실 땐, `variables.tf`와 `terraform.tfvars` 외에도 `main.tf`에 대한 수정이 필요합니다.   


`var.<변수명>` 형식으로 `variables.tf`에서 선언된 변수들을 참조할 수 있으며, 이 과정을 아래 예시 코드를 통해 확인해보세요.

```terraform
# AWS Provider: variables.tf 에서 정의한 리전 사용
provider "aws" {
  region = var.aws_region
  default_tags {
    tags = var.aws_tags
  }
}

# Kubernetes 네임스페이스 생성
resource "kubernetes_namespace" "app_namespace" {
  metadata {
    name = var.namespace # 변수 참조
  }
}

# LiteLLM Deployment 이미지 설정
resource "kubernetes_deployment" "litellm_deployment" {
  # ...
  spec {
    template {
      spec {
        container {
          image = var.litellm_image # 변수 참조
          env_from {
            secret_ref {
              name = kubernetes_secret.app_secrets.metadata[0].name # Secret 참조
            }
          }
        }
      }
    }
  }
}

# Secret에 민감 정보 주입
resource "kubernetes_secret" "app_secrets" {
  metadata {
    name      = "app-secrets"
    namespace = kubernetes_namespace.app_namespace.metadata[0].name
  }
  data = {
    "LITELLM_MASTER_KEY" = var.LITELLM_MASTER_KEY # 민감 변수 참조
    "GEMINI_API_KEY"     = var.GEMINI_API_KEY
    # ...
  }
}

# OpenWebUI Ingress A/B 테스트 가중치 설정
resource "kubernetes_ingress_v1" "openwebui_ingress" {
  metadata {
    annotations = {
      "alb.ingress.kubernetes.io/actions.openwebui-weighted" = jsonencode({
        # ...
        target_groups = [
          {
            serviceName = kubernetes_service.openwebui_v1_service.metadata[0].name
            servicePort = 80
            weight      = var.openwebui_v1_weight # A/B 테스트 가중치 변수 참조
          },
          {
            serviceName = kubernetes_service.openwebui_v2_service.metadata[0].name
            servicePort = 80
            weight      = var.openwebui_v2_weight # A/B 테스트 가중치 변수 참조
          }
        ]
      })
    }
  }
  # ...
}
```

---

```
