resource "yandex_storage_bucket" "archives" {
  bucket        = "${local.prefix}-${var.bucket_name}"
  max_size      = 10 * 1024 * 1024 * 1024
  force_destroy = true

  access_key = yandex_iam_service_account_static_access_key.storage_key.access_key
  secret_key = yandex_iam_service_account_static_access_key.storage_key.secret_key

  depends_on = [yandex_resourcemanager_folder_iam_member.roles]
}