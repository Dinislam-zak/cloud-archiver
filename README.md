# Система архивирования (ВвОТ)

Клиент → API-шлюз → YMQ (tasks) → триггер → Go-функция
(UUIDv7 → download → ZIP → Object Storage + YDB archives).
Ошибочные задания после 1-й неудачи уходят в DLQ.

## Номер студента — одна строка
Все облачные ресурсы именуются `<prefix>-...`, где prefix = `vvot<NN>`.
Номер задаётся ЕДИНСТВЕННО в `terraform/main.tf`:

    locals { student_number = "16" }   # измени на свой номер, напр. "00", "01", "42"

Входных переменных Terraform ровно три (по ТЗ): `cloud_id`, `folder_id`, `bucket_name`.
Номер — `local`, не переменная.

## Требования
- WSL 2 (Ubuntu) или Linux; все файлы LF (`.gitattributes` / `.editorconfig`).
- Go >= 1.21, Terraform >= 1.5, yc CLI (`yc init`), awscli, curl, python3.
- Пользователь `YC_TOKEN`: права admin/editor на folder (создание SA, ролей, ресурсов).
- Имена бакетов глобально уникальны: итог = `<prefix>-<bucket_name>`.

## Запуск

**Шаг 1. Номер студента** (обязательно перед первым apply)

```bash
nano terraform/main.tf   # или любой редактор
# найди строку: student_number = "16"
# измени "16" на свой номер: "00", "01", "42" и т.п.
# сохрани файл
```

**Шаг 2. Переменные окружения и tfvars**

```bash
export YC_TOKEN=$(yc iam create-token)
cd terraform
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars   # впиши свои cloud_id, folder_id, bucket_name
```

**Шаг 3. Сборка зависимостей и деплой**

```bash
cd ..
./scripts/prepare.sh                  # фиксация зависимостей + сборка Go-модулей
cd terraform
terraform init
terraform apply
terraform output gateway_url
```

**После изменения кода функции:**

```bash
cd ..
./scripts/prepare.sh
cd terraform
terraform apply
```

## API

```bash
GW=$(terraform -chdir=terraform output -raw gateway_url)

# Создать задание
curl -X POST "$GW/tasks" -H 'Content-Type: application/json' \
     -d '{"name":"robots","url":"https://www.google.com/robots.txt"}'

# Список всех архивов
curl "$GW/archives"                 # [{name,url,key}, ...]

# Конкретный архив
curl "$GW/archives/<key>"           # {name,url,key} | 404

# Скачать ZIP
curl -OJ "$GW/download/<key>"       # ZIP | 404
```

## Тесты

```bash
./scripts/smoke.sh                  # валидация 400, обработка, список/карточка, ZIP, 404
./scripts/dlq-check.sh              # состояние очередей + сообщения DLQ
```

**DLQ не мгновенный:** после ошибки сообщение ждёт visibility-таймаут очереди (900 с по ТЗ) и переносится при следующем получении. Проверь `dlq-check.sh` через ~15 минут после неудачного задания.

## Чек-лист ТЗ

| Требование | Где |
|---|---|
| Одна TF-конфигурация, 3 переменные, YC_TOKEN | `main.tf`, `variables.tf` |
| Префикс `vvot<NN>-` у всех ресурсов | `locals.student_number` → `local.prefix` |
| Очередь: visibility 900, wait 20, TTL 1 сут, DLQ после 1 попытки | `queues.tf` |
| DLQ: TTL 14 сут | `queues.tf` |
| Функция: 256 МБ / 600 с, Go | `function.tf`, `src/function` |
| Триггер: batch 1 / cutoff 0 | `function.tf` |
| YDB serverless, 1 ГБ, 10 RU/с, документная `archives` | `ydb.tf`, `table.tf` |
| Бакет 10 ГБ, private | `storage.tf` |
| POST /tasks: валидация → 400, иначе очередь | `openapi.yaml.tftpl` |
| GET /archives (Scan), GET /archives/{key} (GetItem, 404) | `openapi.yaml.tftpl` |
| GET /download/{key} (object_storage, 404) | `openapi.yaml.tftpl` |
| UUIDv7 `<uuid>.zip`, запись name/url/key | `src/function` |

## Особенности платформы

- **POST /tasks фактически 200** (passthrough ответа YMQ SendMessage); 202 задекларирован в спеке по ТЗ, подмена кода интеграцией `cloud_ymq` не поддерживается.
- **Валидация тела** включается `x-yc-apigateway-validator` (по умолчанию выключена); errorHandler с dummy-интеграцией гарантирует 400.
- **go.mod функции**: `go 1.21` (≤ рантайм `golang123` = 1.23.9); современный тулчейн не ведёт модуль без директивы. SDK запинен декабрём 2024 (совместимость с Go 1.23, без дефолтных S3-checksum'ов).
- **Имя таблицы `archives`** — без префикса, как явно требует ТЗ (префикс несёт имя БД).
- **Бакет создаётся статическими ключами SA `storage.admin`**: S3 API не определяет folder по IAM-токену пользователя.
- **Статические ключи SA в env функции** — учебный формат; в проде Lockbox/метаданные.

## Удаление

```bash
cd terraform
terraform destroy
```
