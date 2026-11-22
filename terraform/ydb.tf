resource "yandex_ydb_database_serverless" "db" {
  name = "${local.prefix}-db"

  serverless_database {
    storage_size_limit          = 1
    throttling_rcu_limit        = 10
    enable_throttling_rcu_limit = true
  }
}