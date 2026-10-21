#!/bin/bash
# ==============================================================================
# Antigravity Remote Mac Host 一键安装与自启配置脚本
# 支持通过 curl 一键远程执行，或在本地仓库目录直接运行
# ==============================================================================
set -euo pipefail

INSTALL_DIR="$HOME/.gemini/antigravity-remote"
REPO_URL="https://github.com/lilingdeveloper/antigravity-remote.git"
PORT="${PORT:-8789}"

echo "======================================================"
echo "🚀 正在安装 / 配置 Antigravity Remote Mac 端后台服务..."
echo "======================================================"

mkdir -p "$INSTALL_DIR"

# 1. 代码获取与同步
SCRIPT_SOURCE_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    SCRIPT_SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "")"
fi

if [ -n "$SCRIPT_SOURCE_DIR" ] && [ -d "$SCRIPT_SOURCE_DIR/mac-daemon" ]; then
    echo "📦 检测到本地源码目录，正在同步至 $INSTALL_DIR ..."
    rsync -a --exclude '.git' --exclude 'build' --exclude 'TailnetKit.xcframework' "$SCRIPT_SOURCE_DIR/" "$INSTALL_DIR/"
elif [ -d "./mac-daemon" ]; then
    echo "📦 检测到当前目录包含 mac-daemon，正在同步至 $INSTALL_DIR ..."
    rsync -a --exclude '.git' --exclude 'build' --exclude 'TailnetKit.xcframework' "./" "$INSTALL_DIR/"
elif [ -d "$INSTALL_DIR/mac-daemon" ] && [ -d "$INSTALL_DIR/.git" ]; then
    echo "🔄 正在拉取最新代码更新..."
    git -C "$INSTALL_DIR" pull --ff-only 2>/dev/null || true
else
    echo "📥 正在从 GitHub 克隆最新仓库..."
    if command -v git >/dev/null 2>&1; then
        git clone --depth 1 "$REPO_URL" "$INSTALL_DIR" 2>/dev/null || {
            echo "⚠️ Git clone 失败，尝试以 tarball 归档方式下载..."
            curl -fsSL https://github.com/lilingdeveloper/antigravity-remote/archive/refs/heads/main.tar.gz | tar -xz -C "$INSTALL_DIR" --strip-components=1
        }
    else
        curl -fsSL https://github.com/lilingdeveloper/antigravity-remote/archive/refs/heads/main.tar.gz | tar -xz -C "$INSTALL_DIR" --strip-components=1
    fi
fi

# 确保目标目录下 mac-daemon 目录存在
if [ ! -d "$INSTALL_DIR/mac-daemon" ]; then
    echo "❌ 错误: 未能在 $INSTALL_DIR 找到 mac-daemon 目录"
    exit 1
fi

mkdir -p "$INSTALL_DIR/mac-daemon"

# 2. 生成守护进程执行包装脚本 (自动识别内置 Node 运行时)
cat << 'EOF' > "$INSTALL_DIR/run-daemon.sh"
#!/bin/bash
set -euo pipefail

# 自动寻找 Node 运行时 (优先使用 Antigravity 内置环境，完全免额外安装 Node)
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
    echo "[$(date)] 错误: 未找到 Node 运行时，请先安装 Antigravity 或 Node.js" >&2
    exit 1
fi

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PORT="${PORT:-8789}"
export REQUIRE_AUTH="${REQUIRE_AUTH:-true}"
cd "$DIR/mac-daemon"
exec "$NODE_EXEC" "$DIR/mac-daemon/src/server.js"
EOF
chmod +x "$INSTALL_DIR/run-daemon.sh"

# 3. 释放占用端口的旧残留进程
EXISTING_PID=$(lsof -ti :"$PORT" 2>/dev/null || true)
if [ -n "$EXISTING_PID" ]; then
    kill -9 $EXISTING_PID 2>/dev/null || true
    sleep 0.5
fi

# 4. 配置 macOS LaunchAgent 开机静默自启
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST_FILE="$PLIST_DIR/com.liling.antigravity-remote.plist"
mkdir -p "$PLIST_DIR"

# 卸载旧服务
launchctl bootout "gui/$(id -u)/com.liling.antigravity-remote" 2>/dev/null || launchctl unload "$PLIST_FILE" 2>/dev/null || true

cat << EOF > "$PLIST_FILE"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.liling.antigravity-remote</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$INSTALL_DIR/run-daemon.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$INSTALL_DIR/mac-daemon/daemon.log</string>
    <key>StandardErrorPath</key>
    <string>$INSTALL_DIR/mac-daemon/daemon.log</string>
    <key>WorkingDirectory</key>
    <string>$INSTALL_DIR/mac-daemon</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PORT</key>
        <string>$PORT</string>
        <key>REQUIRE_AUTH</key>
        <string>${REQUIRE_AUTH:-true}</string>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin</string>
    </dict>
</dict>
</plist>
EOF

echo "⚙️ 正在注册并启动开机静默守护服务 (LaunchAgent)..."
launchctl bootstrap "gui/$(id -u)" "$PLIST_FILE" 2>/dev/null || launchctl load "$PLIST_FILE"

# 5. 等待服务就绪并自动弹出扫码配对页面
echo "⏳ 等待 Antigravity Remote 桥接服务响应..."
READY=false
for i in $(seq 1 30); do
    if curl -sf "http://127.0.0.1:${PORT}/api/v1/ping" >/dev/null 2>&1; then
        READY=true
        break
    fi
    sleep 0.5
done

if [ "$READY" = true ]; then
    echo "🎉 Antigravity Remote Mac 宿主服务已就绪！"
    echo "📱 正在打开浏览器扫码配对页面..."
    open "http://127.0.0.1:${PORT}/qr" 2>/dev/null || true
    echo ""
    echo "======================================================"
    echo "  配置完成！后续每次 Mac 开机将自动在后台静默运行。"
    echo "  - 扫码配对页: http://127.0.0.1:${PORT}/qr"
    echo "  - 后台运行日志: $INSTALL_DIR/mac-daemon/daemon.log"
    echo "  - 自启配置文件: $PLIST_FILE"
    echo "======================================================"
else
    echo "⚠️ 服务未能在预期时间内响应 (5s)，日志如下："
    cat "$INSTALL_DIR/mac-daemon/daemon.log" 2>/dev/null || true
fi
