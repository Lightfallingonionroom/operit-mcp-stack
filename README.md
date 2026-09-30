# operit-mcp-stack

把自托管 MCP 服务接进 Operit 的通用栈：supergateway 桥接 + 统一启动脚本 + shell 自愈钩子。

## 简介

本项目是 [ncm-mcp](https://github.com/Lightfallingonionroom/ncm-mcp) 的姊妹篇。ncm-mcp 解决「单个服务怎么接进来」，这里解决「接进来之后怎么长期活着」。

运行环境是 Android 上的 Operit + proot Ubuntu：没有 cron，没有 systemd，App 一退出所有进程陪葬。所以整套方案的重点只有两件事——**怎么把 stdio 服务稳定转成 httpStream**，以及**重启之后怎么自动回来**。

## 功能模块

| 模块 | 路径 | 说明 |
|---|---|---|
| 服务管理 | `scripts/start_mcp.sh` | 表驱动（name/port/command），supergateway + fifo 保活 |
| 一键启动 | `scripts/start_all.sh` | NCM 双服务 + MCP 服务一起拉，幂等 |
| 自愈钩子 | `scripts/autostart.sh` | 追加进 `~/.bashrc`，每次开 shell 补齐缺的服务 |
| 接入配置 | `config/mcp_config.example.json` | Operit `mcp_config.json` 片段 |

## 架构

```
Operit (Android)
      │ httpStream (JSON-RPC)
      ▼
supergateway (:3010 / :3014 …)
      │ stdio（stdin 由 fifo 常驻写端持有）
      ▼
paper-search-mcp-nodejs / academix / …
```

> 为什么要 fifo：supergateway 拉起 stdio 子进程时，stdin 若直接接 `/dev/null`，子进程启动即报 `EBADF` 退出。用一个 `mkfifo` + 常驻写端占住 stdin，进程才能稳定挂着。

## 当前服务

| 端口 | 服务 | 来源 | 说明 |
|---|---|---|---|
| 3010 | paper_search | npm `paper-search-mcp-nodejs` | 学术检索，arXiv / Crossref / PubMed 等 14 平台 |
| 3014 | academix | GitHub `xingyulu23/Academix` | 学术元数据聚合，arXiv / Crossref / DBLP / OpenAlex |

`3000`（NCM API）与 `3001`（MCP Adapter）由 [ncm-mcp](https://github.com/Lightfallingonionroom/ncm-mcp) 维护，`start_all.sh` 会一并拉起。

## 部署

### 前置

- Linux 环境（proot / Ubuntu / Debian 均可）
- Node.js ≥ 18 + pnpm
- Python 3.11+（只有 academix 需要）

### 1. 装桥接层

```bash
pnpm add -g supergateway
```

### 2. 装 MCP 服务本体

**paper_search**（npm 包，无依赖负担）

```bash
pnpm add -g paper-search-mcp-nodejs
```

**academix**（Python，需单独 venv）

```bash
git clone https://github.com/xingyulu23/Academix.git /root/mcp_servers/academix
cd /root/mcp_servers/academix
python3 -m venv .venv
.venv/bin/pip install -U pip
.venv/bin/pip install 'mcp<2'
.venv/bin/pip install -e .
```

> `mcp` 必须锁 1.x：2.x 把 `FastMCP` 改名成 `MCPServer`，academix 会直接 `ModuleNotFoundError`。

### 3. 安装脚本

```bash
mkdir -p /root/mcp_servers
cp scripts/start_mcp.sh /root/mcp_servers/
cp scripts/start_all.sh /root/
chmod +x /root/mcp_servers/start_mcp.sh /root/start_all.sh
ln -sf /root/start_all.sh /usr/local/bin/mcp-start

# 自愈钩子：追加进 .bashrc
cat scripts/autostart.sh >> ~/.bashrc
```

### 4. 接入 Operit

编辑 `/sdcard/Download/Operit/mcp_plugins/mcp_config.json`，参考 `config/mcp_config.example.json`。要点是 `connectionType` 用 `httpStream`，endpoint 指向 `http://127.0.0.1:<port>/mcp`。

> endpoint 的 `/mcp` 后缀别漏，否则 Operit 连上去只会拿到 404。

## 常用指令

```bash
mcp-start                      # 一键启动全部
mcp-start status               # 只看状态
/root/mcp_servers/start_mcp.sh restart
/root/mcp_servers/start_mcp.sh log paper_search 50
```

### 加一个新服务

1. 确认它是 stdio 型 MCP（能当命令行进程跑起来）
2. 在 `start_mcp.sh` 的 `SERVICES` 里加一行 `名字|端口|启动命令`
3. **同步 `.bashrc` 钩子里的端口清单**
4. `mcp-start` 验证，再去 Operit 配置里加 endpoint

## 踩坑记录

| 问题 | 原因 | 解决 |
|---|---|---|
| supergateway 启动即 EBADF 退出 | stdin 是 `/dev/null` | `mkfifo` + 常驻写端持有 stdin |
| academix 报 `No module named 'mcp.server.fastmcp'` | 装到了 mcp 2.x | `pip install 'mcp<2'` |
| 重启 Operit 后服务全没 | proot 进程随 App 死亡 | `.bashrc` 钩子 / `mcp-start` |
| 自愈钩子失效过一次就永远不生效 | 目录锁被残留（进程被强杀时没清） | 改用 `flock`，锁随进程释放 |
| 每次开 shell 都空跑一遍启动脚本 | 已删服务仍留在钩子端口清单里 | 端口清单必须与 `SERVICES` 同步 |
| `GET /` 返回 404，以为服务挂了 | 入口是 `POST /mcp`，不响应 GET | 用 `POST /mcp` 探活 |

### 评估后放弃的方案

| 项目 | 放弃原因 |
|---|---|
| conport | venv 单装 4.6GB（向量库 / embedding），磁盘撑不住 |
| thesisagent | 同类重型依赖 |
| scholar_mcp | go-sdk 要求 Go ≥ 1.23，本机 1.22 且 toolchain 下载被墙，仓库无预编译二进制 |
| arxiv-mcp（anuj0456） | 代码是空壳，`run_server()` 里写着 "Server implementation would go here"，未实现 MCP 协议 |

## License

MIT
