#!/bin/bash
# Operit 服务自愈钩子 —— 追加到 ~/.bashrc 末尾使用：
#   cat scripts/autostart.sh >> ~/.bashrc
#
# proot 里没有 cron；Operit 每次进 shell（bash -il）都会读 ~/.bashrc。
# 所以把「健康检查 + 补齐」挂在 shell 启动路径上，等价于开机自启。
# 全部在跑时只做几次本地 TCP 探测，零开销、静默、不污染终端。

# ── Operit 服务自愈钩子（每次开交互 shell 触发）──
# proot 无 cron；Operit 每次进 shell(bash -il) 都会读本文件
# 只在端口不通时拉起 /root/start_all.sh；已运行则零开销、静默
operit_autostart() {
  local need=0
  for p in 3000 3001 3010 3014; do
    (echo > /dev/tcp/127.0.0.1/$p) 2>/dev/null || need=1
  done

  # 都在跑：最常见路径，直接返回
  [ "$need" = 0 ] && return 0

  # flock 串行化：进程被杀时锁自动释放，不会像目录锁那样残留导致永久失效
  ( flock -n 200 || exit 0
    sleep 1
    /root/start_all.sh >> /root/mcp_servers/logs/autostart.log 2>&1
  ) 200>/tmp/.operit_autostart.lock &
  disown
}
[ -x /root/start_all.sh ] && operit_autostart
# ────────────────────────────────────────────────
