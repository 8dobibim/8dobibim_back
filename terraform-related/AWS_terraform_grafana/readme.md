---
## Terraform 변수 및 파라미터 설정 가이드

이 가이드는 인프라 설정을 다루지만, 실제 서비스에 필요한 **API 키**나 **마스터 비밀번호** 같은 민감한 정보는 포함하지 않습니다.

따라서, `terraform apply`를 실행하기 전에 **`tfvars.example` 파일을 참고하여** 개인화된 데이터를 포함하는 **`terraform.tfvars` 파일을 로컬에 설정**하거나 **AWS에서 필요한 정보를 추가해야 합니다.**

여기서는 제공된 `variables.tf` 파일의 내용을 바탕으로 `terraform.tfvars`에 포함될 내용을 설명해 드립니다.

---
### 1. `variables.tf` 파일 이해하기

`variables.tf` 파일은 Terraform 프로젝트에서 사용할 모든 변수를 정의하는 곳입니다. 각 변수는 `variable` 블록으로 선언되며, 다음과 같은 속성을 가질 수 있습니다.

* **`description`**: 변수의 목적을 설명합니다. 명확하고 자세하게 작성하여 다른 사람이 코드를 이해하는 데 도움을 줍니다.
* **`type`**: 변수가 어떤 종류의 값(예: `string`, `number`, `bool`, `list`, `map`)을 받을지 정의합니다.
* **`default`**: 변수에 명시적인 값이 제공되지 않을 경우 사용될 **기본값**을 지정합니다. 개발 환경 등에서 빠르게 테스트할 때 유용합니다.
* **`sensitive`**: `true`로 설정하면 이 변수에 할당된 값이 Terraform 플랜 또는 출력에 표시되지 않도록 숨겨줍니다. **API 키, 비밀번호 등 민감한 정보에 반드시 사용해야 합니다.**

**예시 (`variables.tf` 일부):**

```terraform
variable "namespace" {
  description = "Kubernetes namespace for all resources"
  type        = string
  default     = "default"
}

variable "litellm_master_key" {
  description = "Master API key for LiteLLM"
  type        = string
}
```

---
### 2. `terraform.tfvars` 파일을 통한 변수 값 지정

`variables.tf`에서 변수를 선언했다면, 실제로 Terraform을 실행할 때 이 변수들에 값을 할당해야 합니다. `.tfvars` 파일은 변수 값을 저장하는 가장 일반적인 방법입니다.

프로젝트 루트에 `terraform.tfvars`라는 파일이 있다면, Terraform은 자동으로 이 파일을 로드합니다. 또는 `terraform apply -var-file="example.tfvars"`와 같이 특정 `.tfvars` 파일을 지정할 수도 있습니다.

**`terraform.tfvars` (또는 `tfvars.example`에서 복사하여 수정)**

```terraform
# --- AWS 리전 설정 ---
aws_region = "ap-northeast-2"

# --- EKS 클러스터 설정 ---
cluster_name = "llm-project-eks"
vpc_id = "vpc-0f11e0b7cb225055a" # TODO: 실제 VPC ID로 변경 필요
private_subnet_ids = ["subnet-020d530cbcaed0656", "subnet-06bed7cfb33b120c1"] # TODO: 실제 Subnet ID로 변경 필요
instance_type = "t3.medium"
node_group_desired_capacity = 2
node_group_min_capacity = 1
node_group_max_capacity = 3

# --- Kubernetes 네임스페이스 설정 ---
namespace = "default"

# --- 애플리케이션 포트 설정 ---
litellm_api_port = 4000
litellm_metrics_port = 8000
openwebui_port = 3000
prometheus_port = 9090
grafana_port = 3001

# --- 민감한 환경 변수 및 자격 증명 (매우 중요: 실제 값으로 대체) ---
# 이 값들은 절대로 Git 저장소에 직접 커밋해서는 안 됩니다!
# 대신 `terraform apply -var="VAR_NAME=VALUE"` 또는 CI/CD 파이프라인의 시크릿 관리 기능을 사용하세요.
litellm_master_key = "<YOUR_ACTUAL_LITELLM_MASTER_KEY>" # 반드시 변경
litellm_salt_key = "<YOUR_ACTUAL_LITELLM_SALT_KEY>"     # 반드시 변경
GEMINI_API_KEY = "<YOUR_ACTUAL_GEMINI_API_KEY>"         # 반드시 변경
AZURE_API_KEY = "<YOUR_ACTUAL_AZURE_API_KEY>"           # 반드시 변경
AZURE_API_BASE = "https://your-azure-resource.openai.azure.com/" # 실제 Azure OpenAI Endpoint로 변경
AZURE_API_VERSION = "2023-07-01-preview"                # 실제 API 버전으로 변경

# PostgreSQL 데이터베이스 설정
postgres_user = "<YOUR_ACTUAL_POSTGRES_USER>"           # 반드시 변경
postgres_password = "<YOUR_ACTUAL_POSTGRES_PASSWORD>"   # 반드시 변경
postgres_db = "<YOUR_ACTUAL_POSTGRES_DB_NAME>"          # 반드시 변경
# PostgreSQL 데이터베이스 URL (예: postgresql://user:password@host:port/db)
database_url = "postgresql://<YOUR_ACTUAL_POSTGRES_USER>:<YOUR_ACTUAL_POSTGRES_PASSWORD>@postgres-service:5432/<YOUR_ACTUAL_POSTGRES_DB_NAME>"
```

---
### 번외. `main.tf`에서의 변수 활용

만약, 정의된 변수 외 다른 변수를 활용하거나 설정을 추가하고 싶으실 땐, `variables.tf`와 `terraform.tfvars` 외에도 **`main.tf`에 대한 수정이 필요**합니다.

`var.<변수명>` 형식으로 `variables.tf`에서 선언된 변수들을 참조할 수 있으며, 이 과정을 아래 예시 코드를 통해 확인해보세요.

```terraform
# AWS Provider: variables.tf 에서 정의한 리전 사용
provider "aws" {
  region = var.aws_region
  # main.tf에 aws_tags 변수가 정의되어 있지 않으므로 제거
  # default_tags {
  #   tags = var.aws_tags
  # }
}

# Kubernetes 네임스페이스 (variables.tf에 namespace 변수만 있으므로 그대로 유지)
resource "kubernetes_persistent_volume_claim" "postgres_pvc" {
  metadata {
    name      = "postgres-pvc"
    namespace = var.namespace # 변수 참조
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = { storage = "5Gi" }
    }
    storage_class_name = "gp2"
  }
}

# LiteLLM Deployment (litellm_image 변수가 variables.tf에 없으므로 직접 이미지 사용)
resource "kubernetes_deployment" "litellm_deployment" {
  metadata {
    name      = "litellm"
    namespace = var.namespace
    labels = {
      app = "litellm"
    }
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "litellm"
      }
    }
    template {
      metadata {
        labels = {
          app = "litellm"
        }
      }
      spec {
        container {
          name  = "litellm"
          image = "ghcr.io/berriai/litellm:main" # 변수 대신 직접 이미지 사용

          env {
            name  = "DATABASE_URL"
            value = var.database_url
          }
          env {
            name  = "LITELLM_MASTER_KEY"
            value = var.litellm_master_key
          }
          env {
            name  = "LITELLM_SALT_KEY"
            value = var.litellm_salt_key
          }
          # GEMINI_API_KEY, AZURE_API_KEY, AZURE_API_BASE, AZURE_API_VERSION은 main.tf의 litellm_deployment에 직접 사용되지 않으므로 제거
          # env {
          #   name  = "GEMINI_API_KEY"
          #   value = var.GEMINI_API_KEY
          # }
          # env {
          #   name  = "AZURE_API_KEY"
          #   value = var.AZURE_API_KEY
          # }
          # env {
          #   name  = "AZURE_API_BASE"
          #   value = var.AZURE_API_BASE
          # }
          # env {
          #   name  = "AZURE_API_VERSION"
          #   value = var.AZURE_API_VERSION
          # }

          port {
            container_port = var.litellm_api_port
          }
          port {
            container_port = var.litellm_metrics_port
          }
        }
      }
    }
  }
}

# OpenWebUI Deployment (openwebui_image_v1, openwebui_image_v2 변수가 variables.tf에 없으므로 직접 이미지 사용)
resource "kubernetes_deployment" "openwebui_deployment" {
  metadata {
    name      = "openwebui"
    namespace = var.namespace
    labels = {
      app = "openwebui"
    }
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "openwebui"
      }
    }
    template {
      metadata {
        labels = {
          app = "openwebui"
        }
      }
      spec {
        container {
          name  = "openwebui"
          image = "ghcr.io/open-webui/open-webui:main" # 변수 대신 직접 이미지 사용

          env {
            name  = "DATABASE_URL"
            value = var.database_url
          }
          env {
            name  = "LITELLM_PROXY_BASE_URL"
            value = "http://litellm-service:${var.litellm_api_port}"
          }

          port {
            container_port = var.openwebui_port
          }
        }
      }
    }
  }
}

# Prometheus Deployment (prometheus_image 변수가 variables.tf에 없으므로 직접 이미지 사용)
resource "kubernetes_deployment" "prometheus_deployment" {
  metadata {
    name      = "prometheus"
    namespace = var.namespace
    labels = {
      app = "prometheus"
    }
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "prometheus"
      }
    }
    template {
      metadata {
        labels = {
          app = "prometheus"
        }
      }
      spec {
        container {
          name  = "prometheus"
          image = "prom/prometheus:latest" # 변수 대신 직접 이미지 사용

          port {
            container_port = var.prometheus_port
          }
        }
      }
    }
  }
}

# Grafana Deployment (grafana_image 변수가 variables.tf에 없으므로 직접 이미지 사용)
resource "kubernetes_deployment" "grafana_deployment" {
  metadata {
    name      = "grafana"
    namespace = var.namespace
    labels = {
      app = "grafana"
    }
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "grafana"
      }
    }
    template {
      metadata {
        labels = {
          app = "grafana"
        }
      }
      spec {
        container {
          name  = "grafana"
          image = "grafana/grafana:latest" # 변수 대신 직접 이미지 사용

          port {
            container_port = var.grafana_port
          }
        }
      }
    }
  }
}

# Secret에 민감 정보 주입 (main.tf에 kubernetes_secret 리소스가 없으므로 제거)
# resource "kubernetes_secret" "app_secrets" {
#   metadata {
#     name      = "app-secrets"
#     namespace = kubernetes_namespace.app_namespace.metadata[0].name
#   }
#   data = {
#     "LITELLM_MASTER_KEY" = var.litellm_master_key # 민감 변수 참조
#     "GEMINI_API_KEY"     = var.GEMINI_API_KEY
#     # ...
#   }
# }

# OpenWebUI Ingress A/B 테스트 가중치 설정 (kubernetes_ingress_v1 리소스가 main.tf에 없으므로 제거)
# resource "kubernetes_ingress_v1" "openwebui_ingress" {
#   metadata {
#     annotations = {
#       "alb.ingress.kubernetes.io/actions.openwebui-weighted" = jsonencode({
#         # ...
#         target_groups = [
#           {
#             serviceName = kubernetes_service.openwebui_v1_service.metadata[0].name
#             servicePort = 80
#             weight      = var.openwebui_v1_weight # A/B 테스트 가중치 변수 참조
#           },
#           {
#             serviceName = kubernetes_service.openwebui_v2_service.metadata[0].name
#             servicePort = 80
#             weight      = var.openwebui_v2_weight # A/B 테스트 가중치 변수 참조
#           }
#         ]
#       })
#     }
#   }
#   # ...
# }
```
