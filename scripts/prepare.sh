#!/usr/bin/env bash
# Фиксирует зависимости и проверяет сборку. Запускать в WSL.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== ydb-init =="
(cd src/ydb-init && go mod tidy && go build -o /dev/null .)

echo "== function =="

(cd src/function \
  && go mod edit -go=1.21 \
  && go mod tidy \
  && sed -i '/^toolchain /d' go.mod \
  && go build -o /dev/null .)

echo "OK: модули готовы к деплою"