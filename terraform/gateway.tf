resource "yandex_api_gateway" "gw" {
  name = "${local.prefix}-gateway"

  spec = templatefile("${path.module}/openapi.yaml.tftpl", {
    prefix        = local.prefix
    folder_id     = var.folder_id
    queue_url     = yandex_message_queue.tasks.id
    database_path = yandex_ydb_database_serverless.db.database_path
    bucket_name   = yandex_storage_bucket.archives.bucket
    gateway_sa_id = yandex_iam_service_account.sa["gateway"].id
  })

  depends_on = [yandex_resourcemanager_folder_iam_member.roles]
}