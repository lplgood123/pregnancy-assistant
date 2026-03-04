#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
  echo "未找到 $SCRIPT_DIR/.env"
  echo "请先执行：cp $SCRIPT_DIR/.env.example $SCRIPT_DIR/.env 并填写真实值"
  exit 1
fi

echo "开始构建并启动服务..."
docker compose --env-file "$SCRIPT_DIR/.env" -f "$SCRIPT_DIR/docker-compose.yml" up -d --build

echo "服务状态："
docker compose --env-file "$SCRIPT_DIR/.env" -f "$SCRIPT_DIR/docker-compose.yml" ps

echo "健康检查（HTTP）:"
curl -sS "http://127.0.0.1:8787/healthz" || true

DOMAIN=$(grep '^DOMAIN=' "$SCRIPT_DIR/.env" | cut -d '=' -f2-)
if [[ -n "${DOMAIN:-}" ]]; then
  echo "公网健康检查（HTTPS）:"
  curl -sS "https://${DOMAIN}/healthz" || true
fi
