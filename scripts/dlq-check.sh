#!/usr/bin/env bash
# Состояние очередей + чтение DLQ (без удаления сообщений).
set -u
cd "$(dirname "$0")/.."

export AWS_ACCESS_KEY_ID=$(terraform -chdir=terraform output -raw queue_access_key)
export AWS_SECRET_ACCESS_KEY=$(terraform -chdir=terraform output -raw queue_secret_key)
export AWS_DEFAULT_REGION=ru-central1
EP=https://message-queue.api.cloud.yandex.net
TASKS=$(terraform -chdir=terraform output -raw tasks_queue_url)
DLQ=$(terraform -chdir=terraform output -raw dlq_queue_url)

for q in "$TASKS" "$DLQ"; do
  echo "== $q =="
  aws sqs get-queue-attributes --endpoint-url "$EP" --queue-url "$q" \
    --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible
done

echo "== Сообщения в DLQ =="
aws sqs receive-message --endpoint-url "$EP" --queue-url "$DLQ" \
  --max-number-of-messages 10 --wait-time-seconds 10 --visibility-timeout 5
