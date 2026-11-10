#!/usr/bin/env bash
# 看门狗：容器退出、健康检查失败或入口无响应时自动恢复。
# 由 cron 每 5 分钟触发；存在 logs/.maintenance 时跳过，便于人工停机维护。
set -uo pipefail

DIR=/home/shuias/git/headplane
LOG="$DIR/logs/watchdog.log"
DOCKER=/usr/bin/docker
CONTAINERS=(headplane headscale headplane-dex headplane-traefik)
GRACE=180

cd "$DIR" || exit 1
mkdir -p "$DIR/logs"

say() { echo "$(date '+%F %T') $*" >>"$LOG"; }

if [ -f "$DIR/logs/.maintenance" ]; then
  exit 0
fi

running() { "$DOCKER" ps --format '{{.Names}}' | grep -qx "$1"; }

# 1. 任一容器未运行 → 拉起整个项目（已运行的容器不受影响）
missing=()
for c in "${CONTAINERS[@]}"; do
  running "$c" || missing+=("$c")
done
if [ ${#missing[@]} -gt 0 ]; then
  say "容器未运行：${missing[*]}，执行 compose up"
  "$DOCKER" compose up -d >>"$LOG" 2>&1
  exit 0
fi

# 2. 启动宽限期内不探测，避免把正在启动的服务误判为故障
STARTED=$("$DOCKER" inspect headplane --format '{{.State.StartedAt}}' 2>/dev/null)
if [ -n "$STARTED" ]; then
  START_TS=$(date -d "$STARTED" +%s 2>/dev/null || echo 0)
  if [ $(( $(date +%s) - START_TS )) -lt "$GRACE" ]; then
    exit 0
  fi
fi

# 3. 健康检查失败 → 重启面板
STATUS=$("$DOCKER" inspect headplane --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}' 2>/dev/null)
if [ "$STATUS" = "unhealthy" ]; then
  say "headplane 健康检查为 unhealthy，重启"
  "$DOCKER" restart headplane >>"$LOG" 2>&1
  exit 0
fi

# 4. 入口探测：OIDC 发现文档与登录页都必须可用
for path in "/.well-known/openid-configuration" "/admin/login"; do
  code=$(curl -s -o /dev/null -w '%{http_code}' -m 8 "http://127.0.0.1:8082$path" 2>/dev/null)
  if [ "$code" != "200" ]; then
    say "探测 $path 返回 $code，重启 headplane 与 dex"
    "$DOCKER" restart headplane >>"$LOG" 2>&1
    "$DOCKER" restart headplane-dex >>"$LOG" 2>&1
    exit 0
  fi
done
