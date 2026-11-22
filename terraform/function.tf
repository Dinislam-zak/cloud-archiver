data "archive_file" "function" {
  type        = "zip"
  source_dir  = "${path.module}/../src/function"
  output_path = "${path.module}/build/function.zip"
}

resource "yandex_function" "archiver" {
  name               = "${local.prefix}-archiver"
  description        = "${local.prefix}: URL -> ZIP -> Object Storage + YDB"
  runtime            = "golang123"
  entrypoint         = "index.Handler"
  memory             = 256
  execution_timeout  = "600"
  service_account_id = yandex_iam_service_account.sa["function"].id

  user_hash = data.archive_file.function.output_base64sha256

  content {
    zip_filename = data.archive_file.function.output_path
  }

  environment = {
    BUCKET                = yandex_storage_bucket.archives.bucket
    DOCUMENT_API_ENDPOINT = yandex_ydb_database_serverless.db.document_api_endpoint
    TABLE_NAME            = "archives"
    AWS_REGION            = local.region
    AWS_ACCESS_KEY_ID     = yandex_iam_service_account_static_access_key.function_key.access_key
    AWS_SECRET_ACCESS_KEY = yandex_iam_service_account_static_access_key.function_key.secret_key
  }

  depends_on = [
    null_resource.archives_table,
    yandex_resourcemanager_folder_iam_member.roles,
  ]
}

resource "yandex_function_trigger" "tasks" {
  name = "${local.prefix}-trigger"

  function {
    id                 = yandex_function.archiver.id
    service_account_id = yandex_iam_service_account.sa["trigger"].id
  }

  message_queue {
    queue_id           = yandex_message_queue.tasks.arn
    service_account_id = yandex_iam_service_account.sa["trigger"].id
    batch_size         = 1
    batch_cutoff       = 0
  }

  depends_on = [yandex_resourcemanager_folder_iam_member.roles]
}