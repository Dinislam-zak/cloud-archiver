output "gateway_url" {
  description = "Точка входа для клиентов"
  value       = "https://${yandex_api_gateway.gw.domain}"
}

output "tasks_queue_url" {
  value = yandex_message_queue.tasks.id
}

output "dlq_queue_url" {
  value = yandex_message_queue.dlq.id
}

output "queue_access_key" {
  value     = yandex_iam_service_account_static_access_key.queue_key.access_key
  sensitive = true
}

output "queue_secret_key" {
  value     = yandex_iam_service_account_static_access_key.queue_key.secret_key
  sensitive = true
}