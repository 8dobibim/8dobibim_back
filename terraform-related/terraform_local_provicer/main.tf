# main.tf
# Kubernetes Provider 설정
provider "kubernetes" {
  # 로컬 kubeconfig 파일 (~/.kube/config)을 자동으로 사용합니다.
  # 만약 특정 kubeconfig 파일을 사용하고 싶다면 아래 설정을 추가합니다.
  config_path = "C:\\Users\\Woo\\.kube\\config"
}

# 네임스페이스 생성 (필요 시)

resource "kubernetes_namespace" "app_namespace" {
  metadata {
    name = var.namespace
  }
}

# --- Secrets and ConfigMaps ---

# 민감 정보 (PostgreSQL, LLM API Keys 등)를 위한 Secret
resource "kubernetes_secret" "app_secrets" {
  metadata {
    name      = "app-secrets"
    namespace = var.namespace
  }
  # data 블록에 base64 인코딩된 key-value 쌍을 넣습니다.
  # Terraform Kubernetes provider는 일반 문자열을 data에 넣으면 자동으로 base64 인코딩합니다.
  data = {
    "POSTGRES_USER"         = var.postgres_user
    "POSTGRES_PASSWORD"     = var.postgres_password
    "POSTGRES_DB"           = var.postgres_db
    "GEMINI_API_KEY" = var.GEMINI_API_KEY # 실제 키 변수 사용
    "AZURE_API_KEY" = var.AZURE_API_KEY
    "AZURE_API_BASE" = var.AZURE_API_BASE # variables.tf 에 변수 선언 필수
    "AZURE_API_VERSION" = var.AZURE_API_VERSION # variables.tf 에 변수 선언 필수
    "DATABASE_URL" = var.DATABASE_URL # DATABASE_URL 변수 추가했다면 여기 추가
    "LITELLM_MASTER_KEY" = var.LITELLM_MASTER_KEY # Master Key 변수 추가했다면 여기 추가
    "LITELLM_SALT_KEY" = var.LITELLM_SALT_KEY
    # LiteLLM이 사용하는 다른 필요한 Secret 변수 추가
  }

  type = "Opaque" # 일반적인 키-값 쌍 Secret 타입
}

# LiteLLM 설정 파일 (config.yaml)을 위한 ConfigMap
resource "kubernetes_config_map" "litellm_config" {
  metadata {
    name      = "litellm-config"
    namespace = var.namespace
  }
  data = {
    "config.yaml" = var.litellm_config_content
    # .env 파일 내용을 여기에 넣을 수도 있지만, 변수로 관리하는 것이 더 Terraform스럽습니다.
    # "config.env" = file("${path.module}/litellm.env") # 예시: 로컬 파일 읽기
  }
}

# Prometheus 설정 파일 (prometheus.yml)을 위한 ConfigMap
resource "kubernetes_config_map" "prometheus_config" {
  metadata {
    name      = "prometheus-config"
    namespace = var.namespace
  }
  data = {
    "prometheus.yml" = var.prometheus_config_content
  }
}

# --- PersistentVolumeClaim (for PostgreSQL) ---

resource "kubernetes_persistent_volume_claim" "postgres_pvc" {
  metadata {
    name      = "postgres-pvc"
    namespace = var.namespace
  }
  spec {
    access_modes = ["ReadWriteOnce"] # 단일 Pod에서만 읽기/쓰기 가능
    resources {
      requests = {
        storage = "5Gi" # 필요한 저장 공간 크기 설정 (예: 5GB)
      }
    }
    # storageClassName: 로컬 K8s 환경에 따라 기본 StorageClass가 설정되어 있지 않다면 명시 필요
    # Docker Desktop K8s는 hostpath StorageClass가 기본 제공
    # spec { storage_class_name = "hostpath" } # 필요 시 주석 해제 및 수정
  }
}

# --- Deployments ---

# PostgreSQL Deployment
resource "kubernetes_deployment" "postgres_deployment" {
  metadata {
    name      = "postgres"
    namespace = var.namespace
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "postgres"
      }
    }
    strategy {
      type = "Recreate" # 데이터 유실 방지를 위해 Pod 재생성 시 기존 Pod 종료 후 새 Pod 생성
    }
    template {
      metadata {
        labels = {
          app = "postgres"
        }
      }
      spec {
        container {
          name  = "postgres"
          image = var.postgres_image
          port {
            container_port = var.postgres_port
          }
          # Secret에서 환경 변수 주입
          env_from {
            secret_ref {
              name = kubernetes_secret.app_secrets.metadata[0].name
            }
          }
          env {
            name = "DATABASE_URL" # 기존 설정
            value = "postgresql://litellm_user:4321@postgres:5432/litellm_db"
          }
          # !!! 이곳에 STORE_MODEL_IN_DB 환경 변수를 추가합니다 !!!
          env {
            name = "STORE_MODEL_IN_DB"
            value = "True" # 값은 문자열로 입력합니다.
          }
          volume_mount {
            name       = "postgres-storage"
            mount_path = "/var/lib/postgresql/data" # PostgreSQL 데이터 디렉토리
          }
          # health check (optional but recommended)
          /*
          liveness_probe {
            exec {
              command = ["pg_isready", "-U", "$(POSTGRES_USER)"]
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            timeout_seconds       = 5
            success_threshold     = 1
            failure_threshold     = 6
          }
          readiness_probe {
            exec {
               command = ["pg_isready", "-U", "$(POSTGRES_USER)"]
            }
            initial_delay_seconds = 5
            period_seconds        = 10
            timeout_seconds       = 5
            success_threshold     = 1
            failure_threshold     = 3
          }
          */
        }
        volume {
          name = "postgres-storage"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.postgres_pvc.metadata[0].name
          }
        }
      }
    }
  }
}

# LiteLLM Deployment
resource "kubernetes_deployment" "litellm_deployment" {
  metadata {
    name      = "litellm"
    namespace = var.namespace
    annotations = {
      # Prometheus가 이 Pod를 스크랩하도록 설정 (Prometheus config와 연동)
      "prometheus.io/scrape" = "true"
      "prometheus.io/path"   = "/metrics" # LiteLLM이 노출하는 metrics path
      "prometheus.io/port"   = "${var.litellm_metrics_port}"
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
          image = var.litellm_image
          args = [
            "--config", "/app/config/config.yaml",
            "--host", "0.0.0.0",
            "--port", "${var.litellm_api_port}",
            "--telemetry", "False" # ConfigMap 설정과 일치시키는 것이 좋음
            # --prometheus_url, --prometheus_port 등 필요 시 args나 env로 설정
          ]
          port {
            name = "api"
            container_port = var.litellm_api_port
          }
          port {
            name = "metrics"
            container_port = var.litellm_metrics_port
          }
          # Secret에서 환경 변수 주입 (LLM API 키 등)
          env_from {
            secret_ref {
              name = kubernetes_secret.app_secrets.metadata[0].name
            }
          }
          # ConfigMap에서 환경 변수 주입 (비밀이 아닌 설정)
          # .env 파일 내용을 configmap으로 만든 경우 사용
          /*
          env_from {
            config_map_ref {
              name = "litellm-config" # 또는 .env 파일용 configmap 이름
            }
          }
          */
          # ConfigMap에서 config.yaml 파일 마운트
          volume_mount {
            name       = "litellm-config-volume"
            mount_path = "/app/config" # LiteLLM 컨테이너 내 config 파일 경로
          }
          # PostgreSQL 연결 설정 (환경 변수 또는 config.yaml에 따라 설정)
          # DB 연결 정보는 주로 Secret으로, 호스트는 Service 이름으로 설정
        }
        volume {
          name = "litellm-config-volume"
          config_map {
            name = kubernetes_config_map.litellm_config.metadata[0].name
            # items는 ConfigMap의 특정 키만 마운트할 때 사용
            items {
              key  = "config.yaml"
              path = "config.yaml" # 마운트될 파일 이름
            }
          }
        }
      }
    }
  }
}

# OpenWebUI Deployment (Version 1)
resource "kubernetes_deployment" "openwebui_deployment_v1" {
  metadata {
    name      = "openwebui-v1"
    namespace = var.namespace
  }
  spec {
    replicas = 1 # 각 버전별 Pod 1개
    selector {
      match_labels = {
        app     = "openwebui" # 두 버전의 Deployment가 동일한 라벨 사용
        version = "v1"        # 버전 구분을 위한 라벨
      }
    }
    strategy {
       type = "RollingUpdate"
       rolling_update {
         max_unavailable = "25%"
         max_surge       = "25%"
       }
    }
    template {
      metadata {
        labels = {
          app     = "openwebui"
          version = "v1"
        }
      }
      spec {
        container {
          name  = "openwebui"
          image = var.openwebui_image_v1
          port {
            container_port = var.openwebui_port
          }
          env{
            name = "DEFAULT_MODELS"
            value = "gemini-2.0-flash"
          }
          env {
            name = "OPENAI_API_BASE_URL"
            # LiteLLM 서비스의 ClusterIP와 포트를 사용합니다.
            value = "http://litellm-service:${var.litellm_api_port}"
          }
          env {
            name = "OPENAI_API_KEY"
            value = "dummy-key"
          }
          # OpenWebUI가 필요로 하는 기타 환경 변수/시크릿 주입 (있다면)
          /*
          env_from {
            secret_ref {
              name = kubernetes_secret.app_secrets.metadata[0].name # 또는 OpenWebUI 전용 Secret
            }
          }
          */
        }
      }
    }
  }
}

# OpenWebUI Deployment (Version 2)
resource "kubernetes_deployment" "openwebui_deployment_v2" {
  metadata {
    name      = "openwebui-v2"
    namespace = var.namespace
  }
  spec {
    replicas = 1 # 각 버전별 Pod 1개
    selector {
      match_labels = {
        app     = "openwebui" # 두 버전의 Deployment가 동일한 라벨 사용
        version = "v2"        # 버전 구분을 위한 라벨
      }
    }
    strategy {
       type = "RollingUpdate"
       rolling_update {
         max_unavailable = "25%"
         max_surge       = "25%"
       }
    }
    template {
      metadata {
        labels = {
          app     = "openwebui"
          version = "v2"
        }
      }
      spec {
        container {
          name  = "openwebui"
          image = var.openwebui_image_v2
          port {
            container_port = var.openwebui_port
          }
          env{
            name = "DEFAULT_MODELS"
            value = "gemini-2.0-flash"
          }
          env {
            name = "OPENAI_API_BASE_URL"
            # LiteLLM 서비스의 ClusterIP와 포트를 사용합니다.
            value = "http://litellm-service:${var.litellm_api_port}"
          }
          env {
            name = "OPENAI_API_KEY"
            value = "dummy-key"
          }
          # OpenWebUI가 필요로 하는 기타 환경 변수/시크릿 주입 (있다면)
          /*
          env_from {
            secret_ref {
              name = kubernetes_secret.app_secrets.metadata[0].name # 또는 OpenWebUI 전용 Secret
            }
          }
          */
        }
      }
    }
  }
}

# Prometheus Deployment
resource "kubernetes_deployment" "prometheus_deployment" {
  metadata {
    name      = "prometheus"
    namespace = var.namespace
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "prometheus"
      }
    }
    strategy {
       type = "RollingUpdate"
       rolling_update {
         max_unavailable = "25%"
         max_surge       = "25%"
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
          image = var.prometheus_image
          args = [
            "--config.file=/etc/prometheus/prometheus.yml",
            "--storage.tsdb.path=/prometheus",
            "--web.console.libraries=/usr/share/prometheus/console_libraries",
            "--web.console.templates=/usr/share/prometheus/consoles"
          ]
          port {
            container_port = var.prometheus_port
          }
          volume_mount {
            name       = "prometheus-config-volume"
            mount_path = "/etc/prometheus"
          }
          # 데이터 지속성을 위한 볼륨 마운트 (선택 사항, 로컬 테스트에서는 생략 가능)
          /*
          volume_mount {
            name = "prometheus-data"
            mount_path = "/prometheus"
          }
          */
        }
        volume {
          name = "prometheus-config-volume"
          config_map {
            name = kubernetes_config_map.prometheus_config.metadata[0].name
          }
        }
        # 데이터 지속성을 위한 PVC (선택 사항)
        /*
        volume {
          name = "prometheus-data"
          persistent_volume_claim {
            claim_name = "prometheus-pvc" # 별도로 Prometheus PVC 정의 필요
          }
        }
        */
      }
    }
  }
}


# --- Services ---

# PostgreSQL Service (ClusterIP: 내부 통신용)
resource "kubernetes_service" "postgres_service" {
  metadata {
    name      = "postgres-service" # LiteLLM에서 접근할 서비스 이름
    namespace = var.namespace
  }
  spec {
    selector = {
      app = kubernetes_deployment.postgres_deployment.spec[0].selector[0].match_labels.app
    }
    port {
      protocol    = "TCP"
      port        = var.postgres_port
      target_port = var.postgres_port
    }
    type = "ClusterIP" # 클러스터 내부에서만 접근 가능
  }
}

# LiteLLM Service (ClusterIP: 내부 통신용, OpenWebUI 및 Prometheus에서 접근)
resource "kubernetes_service" "litellm_service" {
  metadata {
    name      = "litellm-service" # OpenWebUI 및 Prometheus에서 접근할 서비스 이름
    namespace = var.namespace
  }
  spec {
    selector = {
      app = kubernetes_deployment.litellm_deployment.spec[0].selector[0].match_labels.app
    }
    port {
      name = "api"
      protocol    = "TCP"
      port        = var.litellm_api_port
      target_port = var.litellm_api_port
      node_port   = var.litellm_service_nodeport
    }
    port {
      name = "metrics" # Prometheus 스크래핑을 위한 포트
      protocol    = "TCP"
      port        = var.litellm_metrics_port
      target_port = var.litellm_metrics_port
    }
    type = "NodePort" # 클러스터 내부에서만 접근 가능
  }
}

# OpenWebUI Service (NodePort: 로컬 환경 외부 접근용)
resource "kubernetes_service" "openwebui_service" {
  metadata {
    name      = "openwebui-service" # 로컬 환경 외부에서 접근할 서비스 이름
    namespace = var.namespace
  }
  spec {
    # 중요한 부분: 두 버전의 Pod를 모두 선택하기 위해 'app: openwebui' 라벨만 사용
    selector = {
      app = "openwebui"
      # 'version' 라벨은 포함하지 않습니다.
    }
    port {
      protocol    = "TCP"
      port        = var.openwebui_port # Service Port (ClusterIP 사용 시 내부 접근 포트)
      target_port = var.openwebui_port # Container Port
      node_port   = var.openwebui_service_nodeport # 로컬 환경 외부에서 접근할 Node Port
    }
    type = "NodePort" # 로컬 환경에서 외부 접근을 위해 NodePort 사용
    # AWS 등으로 옮길 때는 type을 LoadBalancer로 변경
  }
}

# Prometheus Service (NodePort: 로컬 환경 외부 접근용)
resource "kubernetes_service" "prometheus_service" {
  metadata {
    name      = "prometheus-service" # 로컬 환경 외부에서 접근할 서비스 이름
    namespace = var.namespace
  }
  spec {
    selector = {
      app = kubernetes_deployment.prometheus_deployment.spec[0].selector[0].match_labels.app
    }
    port {
      protocol    = "TCP"
      port        = var.prometheus_port # Service Port
      target_port = var.prometheus_port # Container Port
      node_port   = var.prometheus_service_nodeport # 로컬 환경 외부에서 접근할 Node Port
    }
    type = "NodePort" # 로컬 환경에서 외부 접근을 위해 NodePort 사용
  }
}