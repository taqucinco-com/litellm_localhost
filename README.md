# やりたいこと

- [litellm](https://docs.litellm.ai/docs/proxy/docker_quick_start) から利用可能な gemini の model を利用したい
- localhost:4000 から `/v1/messsages` のendpoint で API を叩きたい
- ホストで動いている Ollama のローカルモデルも `gemma4-26b-a4b-q4k` という名前で同じ
  endpoint から叩きたい

# 前提

- GEMINI_API_KEY を [AI Studio](https://aistudio.google.com/app/api-keys) で発行していること
- （gemma を使う場合）ホストで Ollama が起動しており、`gemma4-26b-a4b-q4k` が
  利用可能であること（`ollama run gemma4-26b-a4b-q4k`）

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

使いたいモデルごとに設定ファイルを分けている。中身は `model` だけが異なる。

Gemini API を使う場合:

```{proj_root}/.claude/gemini-settings.json
{
    "model": "gemini-3.5-flash-lite",
    "env": {
        "ANTHROPIC_BASE_URL": "http://localhost:4000",
        "ANTHROPIC_AUTH_TOKEN": "sk-password"
    }
}
```

ホストの Ollama（ローカル LLM）を使う場合:

```{proj_root}/.claude/gemma-settings.json
{
    "model": "gemma4-26b-a4b-q4k",
    "env": {
        "ANTHROPIC_BASE_URL": "http://localhost:4000",
        "ANTHROPIC_AUTH_TOKEN": "sk-password",
        "API_TIMEOUT_MS": "900000",
        "API_FORCE_IDLE_TIMEOUT": "0",
        "CLAUDE_STREAM_IDLE_TIMEOUT_MS": "900000"
    }
}
```

ローカル LLM は長い入力の読み込みに数分かかるため、gemma 用はタイムアウトを
15 分に延ばしている（理由は `docs/adr/202611151449.md`）。

| 変数 | 値 | 意味 |
|---|---|---|
| `API_TIMEOUT_MS` | `900000` | レスポンスヘッダーが届くまで最大 15 分待つ |
| `API_FORCE_IDLE_TIMEOUT` | `0` | ヘッダー待ちを含め 5 分で打ち切るタイマーをオフにする |
| `CLAUDE_STREAM_IDLE_TIMEOUT_MS` | `900000` | ストリーム中の無通信を最大 15 分待つ |

## claude cli

```sh
# Gemini
claude --settings .claude/gemini-settings.json

# ローカルの gemma（Ollama）
claude --settings .claude/gemma-settings.json
```

### gemma では auto mode を使わない

gemma で claude cli を使うときは、auto mode をオフにする（Shift+Tab で
default などのモードに切り替え、コマンドは自分で承認する）。

auto mode では Bash などを実行する前に、コマンドが安全かをモデルに判定させる。
`ANTHROPIC_BASE_URL` を LiteLLM に向けていると、この判定も gemma に送られる。
ローカルの gemma では 1 回の判定に 1 分以上かかり、claude cli 側が約 60 秒で
打ち切る。そのため、コマンドは実行されないまま次のエラーになる。

```
gemma4-26b-a4b-q4k is temporarily unavailable (timed out), so auto mode cannot determine the safety of Bash right now.
```

この打ち切り時間を延ばす設定は claude cli には無い（上の表の
タイムアウトは通常の API リクエスト用で、この判定には効かない）。


# 確認方法

## 1-1. Gemini API キー自体が有効か（LiteLLM を経由せず Google に直接確認）

`.env` の `GEMINI_API_KEY` でそのキーが使えるか、対象モデルが廃止されていないかを確認する。

```bash
curl -s "https://generativelanguage.googleapis.com/v1beta/models?key=$(grep GEMINI_API_KEY .env | cut -d '=' -f2)" | grep '"name"'
```

## 1-2. Ollama がホストで応答するか（gemma を使う場合）

```bash
curl -s http://localhost:11434/api/tags | grep gemma4
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

## 4. `/v1/messages` から実際に Ollama へ転送できるか

```bash
curl -s http://localhost:4000/v1/messages \
  -H "Authorization: Bearer sk-password" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gemma4-26b-a4b-q4k",
    "max_tokens": 64,
    "messages": [{"role": "user", "content": "Say hi in one short sentence."}]
  }'
```

`config.yaml` や `.env` を書き換えた後は、必ず `docker compose restart litellm`
（または `docker compose up -d`）でコンテナに反映してから確認すること。
**環境によっては`docker-compose`で起動**

# ログの削除

`store_prompts_in_spend_logs: true` で有効化されたプロンプト・応答の平文ログを削除する。

```bash
./scripts/purge_message_logs.sh
```

このコマンドは `LiteLLM_SpendLogs` テーブル全体を削除するため、すべての
ログが消える（利用量ログ等も含む）。注意して実行すること。

# LiteLLMのUI

localhost:4000/ui で確認できる。

ID:admin  
PASS:sk-password

# Ollama

Ollama この環境とは別に起動しておき、先にモデルを作成しておくこと。

```sh
# e.g. qwen2.5-coder-7b-instruct-q2_k.gguf
$ ollama serve
$ curl http://127.0.0.1:11434
$ cd ~/Documents/llm/model
$ export $(cat .env | xargs)
$ wget —header=“Authorization: Bearer $HUGGINGFACEHUB_API_TOKEN” -O qwen2.5-coder-7b-instruct-q2_k.gguf \
  'https://huggingface.co/Qwen/Qwen2.5-Coder-7B-Instruct-GGUF/resolve/main/qwen2.5-coder-7b-instruct-q2_k.gguf'
$ cat > Modelfile-qwen2.5-7b-q2_k << 'EOF'
FROM ./qwen2.5-coder-7b-instruct-q2_k.gguf
PARAMETER num_ctx 8192
EOF

ollama create qwen2.5-coder-7b-instruct-q2_k -f Modelfile-qwen2.5-7b-q2_k
$ ollama list
$ ollama run qwen2.5-coder-7b-instruct-q2_k # なにか質問した後 /bye
```
