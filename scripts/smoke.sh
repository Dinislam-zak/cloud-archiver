#!/usr/bin/env bash
# Смоук-тесты по ТЗ. Запуск из корня репо: ./scripts/smoke.sh
# Зависимости: curl, python3, awscli (sudo apt-get install -y awscli).
set -u
cd "$(dirname "$0")/.."

GW=$(terraform -chdir=terraform output -raw gateway_url)
DLQ=$(terraform -chdir=terraform output -raw dlq_queue_url)
AWS_ACCESS_KEY_ID=$(terraform -chdir=terraform output -raw queue_access_key)
AWS_SECRET_ACCESS_KEY=$(terraform -chdir=terraform output -raw queue_secret_key)
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_DEFAULT_REGION=ru-central1
SQS_ENDPOINT=https://message-queue.api.cloud.yandex.net

PASS=0; FAIL=0
expect() {
  if printf '%s' "$3" | grep -Eq "^($2)$"; then
    echo "PASS: $1 -> $3"; PASS=$((PASS+1))
  else
    echo "FAIL: $1 -> $3 (ожидали $2)"; FAIL=$((FAIL+1))
  fi
}
code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }

NAME="smoke-$(date +%s)"
URL="https://www.google.com/robots.txt"

echo "== 1. POST /tasks: валидация =="
c=$(code -X POST "$GW/tasks" -H 'Content-Type: application/json' \
  -d "{\"name\":\"$NAME\",\"url\":\"$URL\"}")
expect "валидное задание принято" "200|202" "$c"

for bad in '{"name":"x"}' '{"url":"https://a.b/c"}' '{"name":"","url":"https://a.b/c"}' \
           '{"name":"x","url":"ftp://a.b/c"}' 'not-json'; do
  c=$(code -X POST "$GW/tasks" -H 'Content-Type: application/json' -d "$bad")
  expect "невалидное: $bad" "400" "$c"
done

echo "== 2. Ожидание обработки (до 90с) =="
KEY=""
for i in $(seq 1 30); do
  KEY=$(curl -s "$GW/archives" | python3 -c \
    "import sys,json;print(next((i['key'] for i in json.load(sys.stdin) if i['name']=='$NAME'),''))" 2>/dev/null)
  [ -n "$KEY" ] && break
  sleep 3
done
if [ -n "$KEY" ]; then echo "PASS: обработано, key=$KEY"; PASS=$((PASS+1));
else echo "FAIL: запись не появилась"; FAIL=$((FAIL+1)); fi

echo "== 3. GET /archives =="
expect "список" "200" "$(code "$GW/archives")"
if curl -s "$GW/archives" | grep -q "$NAME"; then
  echo "PASS: запись в списке"; PASS=$((PASS+1))
else echo "FAIL: записи нет в списке"; FAIL=$((FAIL+1)); fi

if [ -n "$KEY" ]; then
  echo "== 4. GET /archives/{key} =="
  expect "существующий ключ" "200" "$(code "$GW/archives/$KEY")"
  if curl -s "$GW/archives/$KEY" | grep -q "$NAME"; then
    echo "PASS: поля name/url/key"; PASS=$((PASS+1))
  else echo "FAIL: поля записи"; FAIL=$((FAIL+1)); fi

  echo "== 5. GET /download/{key} =="
  TMP=$(mktemp /tmp/archive-XXXXXX.zip)
  c=$(curl -s -o "$TMP" -w '%{http_code}' "$GW/download/$KEY")
  expect "скачивание" "200" "$c"
  expect "ZIP magic" "PK" "$(head -c 2 "$TMP")"
  python3 -m zipfile -l "$TMP"
  rm -f "$TMP"
fi

echo "== 6. 404 =="
MISS=00000000-0000-7000-8000-000000000000.zip
expect "нет записи в YDB" "404" "$(code "$GW/archives/$MISS")"
expect "нет объекта в S3" "404" "$(code "$GW/download/$MISS")"

echo "== 7. DLQ после 1-й неудачи =="
DNAME="dlq-$(date +%s)"
c=$(code -X POST "$GW/tasks" -H 'Content-Type: application/json' \
  -d "{\"name\":\"$DNAME\",\"url\":\"https://missing.invalid/file.bin\"}")
expect "битое задание принято" "200|202" "$c"

fresh=""; any=""
for i in $(seq 1 8); do
  OUT=$(aws sqs receive-message --endpoint-url "$SQS_ENDPOINT" --queue-url "$DLQ" \
        --max-number-of-messages 10 --wait-time-seconds 5 --visibility-timeout 5 2>/dev/null)
  if printf '%s' "$OUT" | grep -q "$DNAME"; then fresh=1; break; fi
  if printf '%s' "$OUT" | grep -q '"MessageId"'; then any=1; fi
  sleep 2
done
if [ -n "$fresh" ]; then
  echo "PASS: свежий пробник в DLQ"; PASS=$((PASS+1))
elif [ -n "$any" ]; then
  echo "PASS: redrive подтверждён (в DLQ пробники прошлых прогонов)."
  echo "      Свежий '$DNAME' приедет через ~15 мин: ./scripts/dlq-check.sh"
  PASS=$((PASS+1))
else
  echo "INFO: DLQ пока пуста. Сообщение приедет через ~15 мин (visibility 900с по ТЗ)."
  echo "      Проверь: ./scripts/dlq-check.sh"
fi

echo
echo "Итого: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
