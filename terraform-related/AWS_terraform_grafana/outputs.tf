# outputs.tf

output "eks_cluster_name" {
  description = "The name of the EKS cluster."
  value       = aws_eks_cluster.main.name
}

output "eks_cluster_endpoint" {
  description = "The endpoint for the EKS cluster."
  value       = aws_eks_cluster.main.endpoint
}

output "eks_cluster_certificate_authority_data" {
  description = "The base64 encoded certificate data required to communicate with your cluster."
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true # 민감 정보이므로 숨김 처리
}

output "litellm_service_url" {
  description = "The URL for the LiteLLM Load Balancer service."
  value       = kubernetes_service.litellm_service.status[0].load_balancer[0].ingress[0].hostname != "" ? "http://${kubernetes_service.litellm_service.status[0].load_balancer[0].ingress[0].hostname}:${var.litellm_api_port}" : "Load Balancer not yet provisioned or external IP not available."
}

output "openwebui_service_url" {
  description = "The URL for the OpenWebUI Load Balancer service."
  value       = kubernetes_service.openwebui_service.status[0].load_balancer[0].ingress[0].hostname != "" ? "http://${kubernetes_service.openwebui_service.status[0].load_balancer[0].ingress[0].hostname}:${var.openwebui_port}" : "Load Balancer not yet provisioned or external IP not available."
}

output "prometheus_service_url" {
  description = "The URL for the Prometheus Load Balancer service."
  value       = kubernetes_service.prometheus_service.status[0].load_balancer[0].ingress[0].hostname != "" ? "http://${kubernetes_service.prometheus_service.status[0].load_balancer[0].ingress[0].hostname}:${var.prometheus_port}" : "Load Balancer not yet provisioned or external IP not available."
}

output "grafana_service_url" {
  description = "The URL for the Grafana Load Balancer service."
  value       = kubernetes_service.grafana_service.status[0].load_balancer[0].ingress[0].hostname != "" ? "http://${kubernetes_service.grafana_service.status[0].load_balancer[0].ingress[0].hostname}:${var.grafana_port}" : "Load Balancer not yet provisioned or external IP not available."
}