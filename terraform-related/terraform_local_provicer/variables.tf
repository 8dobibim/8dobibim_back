# variables.tf
variable "namespace" {
  description = "Kubernetes namespace to deploy resources into"
  type        = string
  default     = "llm-project" # 원하는 네임스페이스로 변경 가능
}

# --- Image Versions ---
variable "litellm_image" {
  description = "LiteLLM Docker image and tag"
  type        = string
  default     = "ghcr.io/berriai/litellm:main-latest" # 사용하려는 LiteLLM 이미지 버전으로 수정
}

variable "openwebui_image_v1" {
  description = "OpenWebUI Docker image and tag for version 1"
  type        = string
  default     = "ghcr.io/open-webui/open-webui:v0.6.7" # 첫 번째 OpenWebUI 버전
}

variable "openwebui_image_v2" {
  description = "OpenWebUI Docker image and tag for version 2"
  type        = string
  default = "ghcr.io/open-webui/open-webui:v0.6.6" # 두 번째 OpenWebUI 버전
}

variable "prometheus_image" {
  description = "Prometheus Docker image and tag"
  type        = string
  default     = "prom/prometheus:v2.47.1" # 사용하려는 Prometheus 이미지 버전으로 수정
}

variable "postgres_image" {
  description = "PostgreSQL Docker image and tag"
  type        = string
  default     = "postgres:13" # 사용하려는 PostgreSQL 이미지 버전으로 수정
}

# --- Ports ---
variable "litellm_api_port" {
  description = "LiteLLM API port"
  type        = number
  default     = 4000
}

variable "litellm_service_nodeport" {
  description = "NodePort for LiteLLM API service (for direct local access)"
  type        = number
  default     = 30001 # 30000-32767 범위 내에서 아직 사용하지 않는 포트 선택
}


variable "litellm_metrics_port" {
  description = "LiteLLM Prometheus metrics port"
  type        = number
  default     = 9000
}

variable "openwebui_port" {
  description = "OpenWebUI application port"
  type        = number
  default     = 8080
}

variable "prometheus_port" {
  description = "Prometheus web UI port"
  type        = number
  default     = 9090
}

variable "postgres_port" {
  description = "PostgreSQL database port"
  type        = number
  default     = 5432
}

variable "openwebui_service_nodeport" {
  description = "NodePort for OpenWebUI service (for local access)"
  type        = number
  default     = 30000 # 30000-32767 범위 내에서 사용 가능한 포트 선택
}

variable "prometheus_service_nodeport" {
  description = "NodePort for Prometheus service (for local access)"
  type        = number
  default     = 30090 # 30000-32767 범위 내에서 사용 가능한 포트 선택
}


# --- Environmental Variables and Configuration (Sensitive handled here) ---
# LiteLLM Credentials

variable "LITELLM_MASTER_KEY" {
  description = "LiteLLM Master Key for authentication/validation"
  type        = string
  sensitive   = true # 민감 정보로 마킹
  # default 값은 설정하지 않거나 더미 값으로 유지하세요.
  # default = "dummy_master_key_replace_me"
}

variable "LITELLM_SALT_KEY" {
  description = "LiteLLM SALT Key for authentication/validation"
  type        = string
  sensitive   = true # 민감 정보로 마킹
  # default 값은 설정하지 않거나 더미 값으로 유지하세요.
  # default = "dummy_master_key_replace_me"
}

variable "GEMINI_API_KEY" {
  description = "GEMINI_API_KEY"
  type        = string
  sensitive   = true # 민감 정보로 마킹
}

variable "AZURE_API_KEY" {
  description = "AZURE_API_KEY"
  type        = string
  sensitive   = true # 민감 정보로 마킹
}

variable "AZURE_API_BASE" {
  description = "AZURE_API_BASE"
  type        = string
  sensitive   = true # 민감 정보로 마킹
}

variable "AZURE_API_VERSION" {
  description = "AZURE_API_VERSION"
  type        = string
  sensitive   = true # 민감 정보로 마킹
}



# PostgreSQL Credentials (Sensitive)
variable "postgres_user" {
  description = "PostgreSQL database user"
  type        = string
  sensitive   = true # 민감 정보로 마킹
}

variable "postgres_password" {
  description = "PostgreSQL database password"
  type        = string
  sensitive   = true # 민감 정보로 마킹
}

variable "postgres_db" {
  description = "PostgreSQL database name"
  type        = string
  sensitive   = true # 민감 정보로 마킹 (DB 이름도 민감할 수 있음)
}

variable "DATABASE_URL" {
  description = "PostgreSQL database url"
  type        = string
  sensitive   = true # 민감 정보로 마킹 (DB 이름도 민감할 수 있음)
}

# LiteLLM API Keys / Configuration specific secrets (Sensitive)
# 실제 사용하는 LLM 프로바이더에 따라 필요한 키를 여기에 추가하세요.
#variable "llm_provider_key_example" {
#  description = "Example API key for an LLM provider"
#  type        = string
#  sensitive   = true
#}

# LiteLLM Config file content (Non-sensitive, can be in ConfigMap)
# 실제 litellm config.yaml 파일 내용을 여기에 복사하거나,
# file() 함수를 사용해서 읽어올 수도 있습니다.
# 여기서는 간단하게 변수로 관리합니다.
variable "litellm_config_content" {
  description = "Content of the LiteLLM config.yaml file"
  type        = string
  default = <<EOF
model_list:
- model_name: gpt-3.5-turbo
  litellm_params:
    model: azure/<your-azure-model-deployment>
    api_base: os.environ/AZURE_API_BASE # runs os.getenv("AZURE_API_BASE")
    api_key: os.environ/AZURE_API_KEY # runs os.getenv("AZURE_API_KEY")
    api_version: "2023-07-01-preview"
- model_name: gemini-2.0-flash
  litellm_params:
    model: gemini/gemini-2.0-flash
    api_key: os.environ/GEMINI_API_KEY 

general_settings:

litellm_settings:
  # 로그 레벨 설정 등
  set_verbose: True
  # Docker 컨테이너 내에서 호스트 머신(예: 로컬 Ollama)에 접근해야 할 경우,
  # Docker 네트워크 설정에 따라 'host.docker.internal' 또는 호스트 IP 직접 사용 필요
  # router_settings:
  #   routing_strategy: simple-shuffle # 또는 다른 라우팅 전략

# 환경 변수를 config 파일 내에서 참조하여 API 키 설정 가능
environment_variables:
EOF
}

# Prometheus Configuration (Non-sensitive)
variable "prometheus_config_content" {
  description = "Content of the Prometheus configuration file (prometheus.yml)"
  type        = string
  default = <<EOF
global:
  scrape_interval: 15s # Set the scrape interval to every 15 seconds. Default is every 1 minute.
  evaluation_interval: 15s # Evaluate rules every 15 seconds. The default is every 1 minute.

scrape_configs:
  - job_name: "kubernetes-pods"
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: true
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
        action: replace
        target_label: __metrics_path__
        regex: (.+)
      - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
        action: replace
        regex: ([^:]+)(?::\d+)?;(\d+)
        replacement: $1:$2
        target_label: __address__
      - action: labelmap
        regex: __meta_kubernetes_pod_label_(.+)
      - source_labels: [__meta_kubernetes_namespace]
        action: replace
        target_label: kubernetes_namespace
      - source_labels: [__meta_kubernetes_pod_name]
        action: replace
        target_label: kubernetes_pod_name

  - job_name: "litellm"
    # LiteLLM 서비스를 타겟팅 (서비스 이름 사용)
    kubernetes_sd_configs:
      - role: endpoints
    relabel_configs:
      - source_labels: [__meta_kubernetes_service_name]
        action: keep
        regex: litellm-service # LiteLLM 서비스 이름과 일치
      - source_labels: [__meta_kubernetes_endpoint_port_name]
        action: keep
        regex: metrics # metrics 포트 이름과 일치
      - source_labels: [__address__]
        target_label: __address__
        regex: ([^:]+)(?::\d+)?
        replacement: $1:9000 # LiteLLM metrics port

EOF
}