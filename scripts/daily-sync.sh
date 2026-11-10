#!/usr/bin/env bash
# 每日同步：上游有新提交时合并到本地 main、推送 fork，并重启服务。
# 无更新时不做任何重启。由 cron 每日 05:00 触发。
set -uo pipefail

DIR=/home/shuias/git/headplane
LOG="$DIR/logs/daily-sync.log"
GIT=/usr/bin/git
DOCKER=/usr/bin/docker

cd "$DIR" || exit 1
mkdir -p "$DIR/logs"

say() { echo "$(date '+%F %T') $*" >>"$LOG"; }

say "===== 检查上游更新 ====="
if ! "$GIT" fetch upstream >>"$LOG" 2>&1; then
  say "拉取 upstream 失败，本次跳过"
  exit 1
fi

if "$GIT" merge-base --is-ancestor upstream/main main; then
  say "上游无新提交，无需更新"
  exit 0
fi

AHEAD=$("$GIT" rev-list --count main..upstream/main)
say "发现上游新提交 $AHEAD 个，开始合并"

if ! "$GIT" merge --no-edit upstream/main >>"$LOG" 2>&1; then
  "$GIT" merge --abort >>"$LOG" 2>&1
  say "合并冲突，已回滚本地改动，需人工处理"
  exit 1
fi

if "$GIT" push origin main >>"$LOG" 2>&1; then
  say "已推送 fork：origin/main 更新到 $("$GIT" rev-parse --short HEAD)"
else
  say "推送 fork 失败，本地已合并，等待下次重试"
fi

say "拉取镜像并重建服务"
"$DOCKER" compose pull >>"$LOG" 2>&1
"$DOCKER" compose up -d >>"$LOG" 2>&1

sleep 15
UNHEALTHY=$("$DOCKER" ps --filter health=unhealthy --format '{{.Names}}' | tr '\n' ' ')
if [ -n "$UNHEALTHY" ]; then
  say "重启后仍有不健康容器：$UNHEALTHY"
else
  say "更新完成，当前提交 $("$GIT" rev-parse --short HEAD)"
fi
