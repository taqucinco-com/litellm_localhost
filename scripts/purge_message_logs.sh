#!/bin/sh
# store_prompts_in_spend_logs により平文で保存された LiteLLM_SpendLogs の
# 会話ログ（response / proxy_server_request カラムのプロンプト・応答本文）
# を削除する。
set -eu

docker exec litellm-db-1 psql -U litellm -d litellm \
  -c 'DELETE FROM "LiteLLM_SpendLogs";'
