locals {
  service_accounts = {
    gateway  = ["ymq.writer", "ydb.editor", "storage.viewer"]
    function = ["storage.uploader", "ydb.editor"]
    trigger  = ["ymq.reader", "ymq.writer", "serverless.functions.invoker"]
    queue    = ["ymq.admin"]
    storage  = ["storage.admin"]
  }

  sa_roles = merge([
    for name, roles in local.service_accounts : {
      for role in roles : "${name}:${role}" => { sa = name, role = role }
    }
  ]...)
}

resource "yandex_iam_service_account" "sa" {
  for_each = local.service_accounts
  name     = "${local.prefix}-sa-${each.key}"
}

resource "yandex_resourcemanager_folder_iam_member" "roles" {
  for_each  = local.sa_roles
  folder_id = var.folder_id
  role      = each.value.role
  member    = "serviceAccount:${yandex_iam_service_account.sa[each.value.sa].id}"
}

resource "yandex_iam_service_account_static_access_key" "function_key" {
  service_account_id = yandex_iam_service_account.sa["function"].id
  description        = "${local.prefix} function: S3 + YDB Document API"
}

resource "yandex_iam_service_account_static_access_key" "queue_key" {
  service_account_id = yandex_iam_service_account.sa["queue"].id
  description        = "${local.prefix} terraform: YMQ management"
}

resource "yandex_iam_service_account_static_access_key" "storage_key" {
  service_account_id = yandex_iam_service_account.sa["storage"].id
  description        = "${local.prefix} terraform: bucket management"
}