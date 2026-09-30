#!/bin/bash
# Operit 一键启动：本地自托管服务
#   网易云 API :3000 / MCP Adapter :3001   （见 ncm-mcp 仓库）
#   paper_search :3010 / academix :3014    （由 start_mcp.sh 管理）
#
# 用法: bash /root/start_all.sh   |   mcp-start   |   mcp-start status
#
# 幂等：子脚本各自探活，已在跑的会跳过。

if [ "$1" = "status" ]; then
  [ -x /root/ncm.sh ] && { /root/ncm.sh all status; echo; }
  /root/mcp_servers/start_mcp.sh status
  exit 0
fi

if [ -x /root/ncm.sh ]; then
  echo "== [1/2] 网易云 API + MCP Adapter =="
  /root/ncm.sh all start
  echo
fi

echo "== [2/2] MCP 服务 =="
/root/mcp_servers/start_mcp.sh start
echo

echo "== 状态总览 =="
[ -x /root/ncm.sh ] && { /root/ncm.sh all status; echo; }
/root/mcp_servers/start_mcp.sh status
