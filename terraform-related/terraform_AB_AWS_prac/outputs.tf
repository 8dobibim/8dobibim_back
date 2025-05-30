# outputs.tf
output "openwebui_url" {
  description = "OpenWebUI service URL (NodePort)"
  value = "http://localhost:${kubernetes_service.openwebui_service.spec[0].port[0].node_port}" # <--- 수정 완료  # 로컬 환경에서 NodePort는 일반적으로 localhost로 접근 가능합니다.
  # 실제 Node IP를 사용해야 하는 경우, 아래와 같이 수정할 수 있습니다.
  # value = "http://${kubernetes_service.openwebui_service.spec[0].external_ips[0]}:${kubernetes_service.openwebui_service.spec[0].node_port}"
}

output "prometheus_url" {
  description = "Prometheus service URL (NodePort)"
  value = "http://localhost:${kubernetes_service.prometheus_service.spec[0].port[0].node_port}" # <--- 수정 완료
  # value = "http://localhost:${kubernetes_service.prometheus_service.spec[0].node_port}"
  # 실제 Node IP를 사용해야 하는 경우, 위와 같이 수정
}

output "litellm_service_name" {
  description = "LiteLLM ClusterIP Service Name"
  value = kubernetes_service.litellm_service.metadata[0].name
}

output "litellm_api_url" {
  description = "LiteLLM API service URL (NodePort for direct access)"
  # spec[0].port[0].node_port 와 같이 참조합니다. port 블록이 리스트입니다.
  value = "http://localhost:${kubernetes_service.litellm_service.spec[0].port[0].node_port}"
}

output "litellm_metrics_url" {
  description = "LiteLLM Metrics URL (NodePort)"
  value = "http://localhost:${kubernetes_service.litellm_service.spec[0].port[1].node_port}"
}


output "postgres_service_name" {
  description = "PostgreSQL ClusterIP Service Name"
  value = kubernetes_service.postgres_service.metadata[0].name
}