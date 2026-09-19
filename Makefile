.PHONY: up down clear-log

up:
	docker compose up -d

down:
	docker compose down

clear-log:
	./scripts/purge_message_logs.sh
