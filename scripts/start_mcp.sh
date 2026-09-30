#!/bin/bash
# MCP 服务统一管理脚本（supergateway + fifo 保活）
#
# 用法:
#   ./start_mcp.sh start|stop|restart|status
#   ./start_mcp.sh log <name> [行数]
#
# 新增服务：在 SERVICES 里加一行「名字|端口|启动命令」
# 注意：改完记得同步 ~/.bashrc 钩子里的端口清单

export PATH="/root/.local/share/pnpm/bin:$PATH"
LOGDIR=/root/mcp_servers/logs
FIFODIR=/root/mcp_servers/fifos
mkdir -p "$LOGDIR" "$FIFODIR"

# name|port|command
SERVICES=(
  "paper_search|3010|paper-search-mcp-nodejs"
  "academix|3014|/root/mcp_servers/academix/.venv/bin/academix"
)

port_running(){ curl -s -o /dev/null --max-time 2 -X POST "http://127.0.0.1:$1/mcp" -H 'Content-Type: application/json' -d '{}' 2>/dev/null; [ $? -eq 0 ] && return 0; return 1; }

start_one(){
  local name=$1 port=$2 cmd=$3
  local fifo=$FIFODIR/$name.fifo
  if port_running $port; then echo "[$name] 已在 :$port 运行"; return 0; fi
  rm -f "$fifo"; mkfifo "$fifo"
  # fifo 需要一个常驻写端，否则子进程拿到 EOF/EBADF 后启动即退
  (while true; do sleep 3600; done > "$fifo" &)
  nohup supergateway --stdio "$cmd" --port "$port" --outputTransport streamableHttp < "$fifo" > "$LOGDIR/$name.log" 2>&1 &
  echo "[$name] 启动 pid=$! 端口=$port"
  sleep 4
  if port_running $port; then echo "[$name] OK 已就绪 :$port"; else echo "[$name] 未就绪，看日志 $LOGDIR/$name.log"; fi
}

stop_all(){
  pkill -f "supergateway --stdio" 2>/dev/null
  pkill -f "sleep 3600" 2>/dev/null
  echo "已全部停止"
}

status(){
  echo "端口  服务         状态"
  for s in "${SERVICES[@]}"; do
    IFS='|' read -r name port cmd <<< "$s"
    if port_running $port; then st="运行中"; else st="未运行"; fi
    printf "%-6s%-14s%s\n" "$port" "$name" "$st"
  done
}

logs(){ tail -n "${2:-30}" "$LOGDIR/$1.log"; }

case "${1:-start}" in
  start)   for s in "${SERVICES[@]}"; do IFS='|' read -r n p c <<< "$s"; start_one "$n" "$p" "$c"; done ;;
  stop)    stop_all ;;
  restart) stop_all; sleep 2; for s in "${SERVICES[@]}"; do IFS='|' read -r n p c <<< "$s"; start_one "$n" "$p" "$c"; done ;;
  status)  status ;;
  log)     logs "$2" "$3" ;;
  *) echo "用法: $0 start|stop|restart|status|log <name> [行数]" ;;
esac
