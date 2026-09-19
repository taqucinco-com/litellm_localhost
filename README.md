# やりたいこと

- [litellm](https://docs.litellm.ai/docs/proxy/docker_quick_start) から利用可能な gemini の model を利用したい
- localhost:4000 から `/v1/messsages` のendpoint で API を叩きたい

# 前提

- GEMINI_API_KEY を [AI Studio](https://aistudio.google.com/app/api-keys) で発行していること

# なぜ

```
export ANTHROPIC_BASE_URL=http://localhost:4000
export ANTHROPIC_AUTH_TOKEN=sk-password
```

に設定すると claude cli での model に gemini が使えるようになる。  
Flash-Lite シリーズは、APIの無料利用枠（Free Tier）として多めの上限が割り当てられているためclaudeのトークン消費を抑えるのに利用できる。

# claude側の設定

claude cliをlitellm経由で使うために以下のような設定ファイルを置く。

常用の Anthropic API 設定とは別ファイルにして
`--settings` で明示的に読み込む。

## 設定ファイル

```{proj_root}/.claude/gemini-settings.json
{
    "model": "gemini-3.5-flash-lite",
    "env": {
        "ANTHROPIC_BASE_URL": "http://localhost:4000",
        "ANTHROPIC_AUTH_TOKEN": "sk-password"
    }
}
```

## claude cli

```sh
claude --settings .claude/gemini-settings.json
```


# 確認方法

## 1. Gemini API キー自体が有効か（LiteLLM を経由せず Google に直接確認）

`.env` の `GEMINI_API_KEY` でそのキーが使えるか、対象モデルが廃止されていないかを確認する。

```bash
curl -s "https://generativelanguage.googleapis.com/v1beta/models?key=$(grep GEMINI_API_KEY .env | cut -d '=' -f2)" | grep '"name"'
```

## 2. LiteLLM Proxy にモデルが登録されているか

`config.yaml` が正しく読み込まれていれば、モデル一覧が返る（空配列や 404 の場合は
`docker compose restart litellm` で読み込み直す）。

```bash
curl -s http://localhost:4000/v1/models \
  -H "Authorization: Bearer sk-password"
```

## 3. `/v1/messages` から実際に Gemini へ転送できるか

```bash
curl -s http://localhost:4000/v1/messages \
  -H "Authorization: Bearer sk-password" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gemini-3.5-flash-lite",
    "max_tokens": 64,
    "messages": [{"role": "user", "content": "Say hi in one short sentence."}]
  }'
```

`config.yaml` や `.env` を書き換えた後は、必ず `docker compose restart litellm`
（または `docker compose up -d`）でコンテナに反映してから確認すること。

# ログの削除

`store_prompts_in_spend_logs: true` で有効化されたプロンプト・応答の平文ログを削除する。

```bash
./scripts/purge_message_logs.sh
```

このコマンドは `LiteLLM_SpendLogs` テーブル全体を削除するため、すべての
ログが消える（利用量ログ等も含む）。注意して実行すること。

# LiteLLMのUI

localhost:4000/ui で確認できる。
