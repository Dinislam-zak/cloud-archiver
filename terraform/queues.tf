resource "yandex_message_queue" "dlq" {
  name                      = "${local.prefix}-dlq"
  message_retention_seconds = 1209600
  
  access_key = yandex_iam_service_account_static_access_key.queue_key.access_key
  secret_key = yandex_iam_service_account_static_access_key.queue_key.secret_key

  depends_on = [yandex_resourcemanager_folder_iam_member.roles]
}

resource "yandex_message_queue" "tasks" {
  name                       = "${local.prefix}-tasks"
  visibility_timeout_seconds = 900
  receive_wait_time_seconds  = 20
  message_retention_seconds  = 86400

  redrive_policy = jsonencode({
    deadLetterTargetArn = yandex_message_queue.dlq.arn
    maxReceiveCount     = 1
  })

  access_key = yandex_iam_service_account_static_access_key.queue_key.access_key
  secret_key = yandex_iam_service_account_static_access_key.queue_key.secret_key

  depends_on = [yandex_resourcemanager_folder_iam_member.roles]
}