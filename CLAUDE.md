# CLAUDE.md

## 応答言語

あなたの返答は日本語で行うこと。

## 意思決定の記録（ADR）

モデル選定の理由や構成変更の背景など「なぜそうしたか」という意思決定は
README.md には書かず、`docs/adr/yyyyMMddhhmm.md`（`date +%Y%m%d%H%M`）と
いうファイル名で ADR として残すこと。README.md / CLAUDE.md には現在の
状態・使い方のみを書き、変更の経緯は ADR を参照する。

## プロジェクト概要

LiteLLM Proxy をローカルの Docker Compose で起動し、Gemini API 経由で
`gemini-3.5-flash-lite` という名前のモデルを、Anthropic 互換の
`http://localhost:4000/v1/messages` エンドポイントから叩けるようにする構成。
あわせて、ホストで稼働している Ollama のローカルモデルを `gemma4-26b-a4b-q4k`
という名前で登録しており（`ollama_chat/` 経由、`http://host.docker.internal:11434`）、
リクエストの `model` で Gemini とローカル LLM を切り替えられる
（経緯は `docs/adr/202611151348.md`）。

- `docker-compose.yml`: LiteLLM Proxy 本体（`litellm` サービス）と、モデル・
  仮想キー・利用ログを保存する Postgres（`db` サービス）を起動する。
- `config.yaml`: LiteLLM に登録するモデル一覧（`model_list`）と管理者設定
  （`general_settings`）を定義する。

## 起動・再起動

```bash
docker compose up -d
```

`config.yaml` を編集した場合はホットリロードされないため、必ず
`litellm` コンテナを再起動すること。

```bash
docker compose restart litellm
```

## ハマりどころ

- **`config.yaml` を書いただけでは読み込まれない。** LiteLLM の Docker
  イメージのデフォルト起動コマンドは `litellm --port 4000` で、`--config`
  オプションが付いていないと `/app/config.yaml` をマウントしていても無視
  される。`docker-compose.yml` の `litellm` サービスに
  `command: ["--config", "/app/config.yaml", "--port", "4000"]` を明示して
  いる。これが無いと UI の `models-and-endpoints` ページが
  `no models found` のまま、`/v1/models` も空配列を返す。
- **Gemini のモデル名は頻繁に廃止される。** `gemini-1.5-flash` や
  `gemini-2.5-flash` は既に新規利用不可になっている。`config.yaml` の
  `model_name`（クライアントから見える名前）と `litellm_params.model`
  （実際に LiteLLM が呼び出す先）は同じ `gemini-3.5-flash-lite` にして
  いるが、廃止モデルが出た場合は `litellm_params.model` 側だけ差し替え
  ればよい。個別バージョン名の代わりに `gemini/gemini-flash-lite-latest`
  のようなエイリアス（Google が常に最新の lite モデルを指すよう管理）に
  戻す選択肢もある。利用可能なモデル一覧は以下で確認できる。

  ```bash
  curl -s "https://generativelanguage.googleapis.com/v1beta/models?key=<GEMINI_API_KEY>"
  ```
- **API キーは `config.yaml` / `docker-compose.yml` に直書きしない。**
  `GEMINI_API_KEY` は `.env`（gitignore 済み）に置き、`docker-compose.yml`
  では `${GEMINI_API_KEY}` で参照、`config.yaml` では LiteLLM 独自の
  `os.environ/GEMINI_API_KEY` 記法でコンテナ内の環境変数を参照させている。
  `.env` の値を更新した場合も、反映には `litellm` コンテナの再起動が要る。
- **claude cli の `settings.json` に `profiles` キーや `--profile` フラグは
  存在しない。** 複数設定を切り替えたい場合は設定ファイルを分けて
  `claude --settings <path>` で明示的に読み込む（詳細は README.md
  「claude側の設定」を参照）。
- **`gemma4-26b-a4b-q4k` を使うには Ollama をホスト側で起動しておく必要がある。** LiteLLM コンテナからは
  `host.docker.internal:11434` でホストの Ollama に接続する。
  `ollama list` に `gemma4-26b-a4b-q4k` が出ていること、
  `curl http://localhost:11434/api/tags` が応答することを確認する。
- **gemma4 の thinking は `think: false` で無効化している。** 有効だと
  思考だけで `max_tokens` を使い切り、`text` が空で返る。
- **Ollama のコンテキスト長は `config.yaml` の `num_ctx: 65536` で広げている。**
  Ollama のモデルは Modelfile の `PARAMETER num_ctx 8192` で作成されており、
  これを超えた入力は黙って切り捨てられる（実際に届くのは半分程度の 4099
  トークン前後）。claude cli のツール定義が届かず、存在しないツール
  （`shell` 等）を呼んだり、宣言だけして何もしなくなる。リクエスト側の
  `num_ctx` が Modelfile の値より優先されるため、Modelfile を作り直す必要は
  ない。現在の値は `ollama ps` の `CONTEXT` 列、Modelfile の値は
  `ollama show <model> --parameters` で確認できる。切り捨ての有無は
  `LiteLLM_SpendLogs` の `prompt_tokens` が頭打ちになっていないかで判別できる。

## 動作確認

```bash
curl http://localhost:4000/v1/messages \
  -H "Authorization: Bearer sk-password" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gemini-3.5-flash-lite",
    "max_tokens": 64,
    "messages": [{"role": "user", "content": "Say hi in one short sentence."}]
  }'
```
