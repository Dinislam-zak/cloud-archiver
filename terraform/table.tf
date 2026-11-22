resource "null_resource" "archives_table" {
  depends_on = [
    yandex_ydb_database_serverless.db,
    yandex_resourcemanager_folder_iam_member.roles,
  ]

  triggers = {
    db_id = yandex_ydb_database_serverless.db.id
  }

  provisioner "local-exec" {
    working_dir = "${path.module}/../src/ydb-init"
    command     = "go run ."
    environment = {
      AWS_ACCESS_KEY_ID         = yandex_iam_service_account_static_access_key.function_key.access_key
      AWS_SECRET_ACCESS_KEY     = yandex_iam_service_account_static_access_key.function_key.secret_key
      AWS_REGION                = local.region
      AWS_EC2_METADATA_DISABLED = "true"
      DOCUMENT_API_ENDPOINT     = yandex_ydb_database_serverless.db.document_api_endpoint
      TABLE_NAME                = "archives"
    }
  }
}