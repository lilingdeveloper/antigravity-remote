#!/bin/bash
#
# start-mac-host.sh · 极简 Mac 端静默桥接启动器
# 作用：自动探测本机 Antigravity 的动态端口与 CSRF Token，并暴露给手机端连接 (端口 8789)
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DAEMON_DIR="$ROOT_DIR/mac-daemon"

# 自动定位 Node 运行时 (优先使用 Antigravity 内置环境，无需用户额外安装 Node.js)
NODE_EXEC=""
if [ -x "$HOME/Library/Application Support/Antigravity/bin/agy-node" ]; then
  NODE_EXEC="$HOME/Library/Application Support/Antigravity/bin/agy-node"
elif [ -x "/Applications/Antigravity.app/Contents/Frameworks/Antigravity Helper.app/Contents/MacOS/Antigravity Helper" ]; then
  export ELECTRON_RUN_AS_NODE=1
  NODE_EXEC="/Applications/Antigravity.app/Contents/Frameworks/Antigravity Helper.app/Contents/MacOS/Antigravity Helper"
elif command -v node >/dev/null 2>&1; then
  NODE_EXEC="$(command -v node)"
elif [ -x "/opt/homebrew/bin/node" ]; then
  NODE_EXEC="/opt/homebrew/bin/node"
elif [ -x "/usr/local/bin/node" ]; then
  NODE_EXEC="/usr/local/bin/node"
fi

if [ -z "$NODE_EXEC" ]; then
  echo "❌ 未找到 Node 运行时，请确保已安装 Antigravity 或 Node.js"
  exit 1
fi

export PORT="${PORT:-8789}"
export REQUIRE_AUTH="${REQUIRE_AUTH:-true}"

# 如果已在运行则先平滑终止现有进程
EXISTING_PID=$(lsof -ti :"$PORT" 2>/dev/null || true)
if [ -n "$EXISTING_PID" ]; then
  kill -9 $EXISTING_PID 2>/dev/null || true
  sleep 0.5
fi

nohup "$NODE_EXEC" "$DAEMON_DIR/src/server.js" > "$DAEMON_DIR/daemon.log" 2>&1 &
NEW_PID=$!
sleep 1

cat "$DAEMON_DIR/daemon.log"
echo "📌 后台守护进程 PID: $NEW_PID (日志文件: $DAEMON_DIR/daemon.log)"
