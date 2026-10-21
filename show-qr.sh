#!/usr/bin/env bash
# 一键在 Mac 端弹出扫码配对窗口 (或打印终端二维码)
PORT="${PORT:-8789}"
open "http://127.0.0.1:${PORT}/qr"
echo "✅ 已在浏览器打开扫码配对页面: http://127.0.0.1:${PORT}/qr"
