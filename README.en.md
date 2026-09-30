# operit-mcp-stack

[中文](README.md) | **English**

A general-purpose stack for plugging self-hosted MCP servers into Operit: supergateway bridge + unified launcher + shell self-healing hook.

## Overview

This is the sibling project of [ncm-mcp](https://github.com/Lightfallingonionroom/ncm-mcp). ncm-mcp answers "how do I hook up one service"; this one answers "how do I keep it alive afterwards".

The runtime is Operit on Android plus a proot Ubuntu: no cron, no systemd, and every process dies together with the app. So the whole design boils down to two questions — **how to turn a stdio server into a stable httpStream endpoint**, and **how to come back automatically after a restart**.

## Modules

| Module | Path | Description |
|---|---|---|
| Service manager | `scripts/start_mcp.sh` | Table-driven (name/port/command), supergateway + fifo keep-alive |
| One-shot launcher | `scripts/start_all.sh` | Brings up the NCM pair and the MCP servers together, idempotent |
| Self-heal hook | `scripts/autostart.sh` | Append to `~/.bashrc`; fills in whatever is missing on every shell start |
| Client config | `config/mcp_config.example.json` | Snippet for Operit's `mcp_config.json` |

## Architecture

```
Operit (Android)
      │ httpStream (JSON-RPC)
      ▼
supergateway (:3010 / :3014 …)
      │ stdio (stdin held open by a fifo writer)
      ▼
paper-search-mcp-nodejs / academix / …
```

> Why the fifo: when supergateway spawns a stdio child with stdin pointed at `/dev/null`, the child dies immediately with `EBADF`. Holding stdin open with a `mkfifo` plus a resident writer is what keeps the process alive.

## Services

| Port | Service | Source | Notes |
|---|---|---|---|
| 3010 | paper_search | npm `paper-search-mcp-nodejs` | Literature search across arXiv / Crossref / PubMed and 11 more platforms |
| 3014 | academix | GitHub `xingyulu23/Academix` | Scholarly metadata aggregation: arXiv / Crossref / DBLP / OpenAlex |

`3000` (NCM API) and `3001` (MCP adapter) are maintained by [ncm-mcp](https://github.com/Lightfallingonionroom/ncm-mcp); `start_all.sh` brings them up as well.

## Deployment

### Requirements

- Linux (proot / Ubuntu / Debian all fine)
- Node.js ≥ 18 with pnpm
- Python 3.11+ (academix only)

### 1. Bridge layer

```bash
pnpm add -g supergateway
```

### 2. MCP servers

**paper_search** (npm package, no dependency baggage)

```bash
pnpm add -g paper-search-mcp-nodejs
```

**academix** (Python, needs its own venv)

```bash
git clone https://github.com/xingyulu23/Academix.git /root/mcp_servers/academix
cd /root/mcp_servers/academix
python3 -m venv .venv
.venv/bin/pip install -U pip
.venv/bin/pip install 'mcp<2'
.venv/bin/pip install -e .
```

> Pin `mcp` to 1.x. Version 2.x renamed `FastMCP` to `MCPServer`, and academix fails with a plain `ModuleNotFoundError`.

### 3. Scripts

```bash
mkdir -p /root/mcp_servers
cp scripts/start_mcp.sh /root/mcp_servers/
cp scripts/start_all.sh /root/
chmod +x /root/mcp_servers/start_mcp.sh /root/start_all.sh
ln -sf /root/start_all.sh /usr/local/bin/mcp-start

# self-heal hook
cat scripts/autostart.sh >> ~/.bashrc
```

### 4. Operit integration

Edit `/sdcard/Download/Operit/mcp_plugins/mcp_config.json`; see `config/mcp_config.example.json`. The essentials are `connectionType: httpStream` and an endpoint of `http://127.0.0.1:<port>/mcp`.

> Don't drop the `/mcp` suffix, otherwise Operit only ever gets a 404.

## Usage

```bash
mcp-start                      # start everything
mcp-start status               # status only
/root/mcp_servers/start_mcp.sh restart
/root/mcp_servers/start_mcp.sh log paper_search 50
```

### Adding a server

1. Make sure it is a stdio MCP server that runs as a plain command
2. Add a `name|port|command` line to `SERVICES` in `start_mcp.sh`
3. **Keep the port list in the `.bashrc` hook in sync**
4. Verify with `mcp-start`, then add the endpoint to Operit's config

## Gotchas

| Problem | Cause | Fix |
|---|---|---|
| supergateway exits with EBADF on start | stdin is `/dev/null` | `mkfifo` plus a resident writer to hold stdin |
| academix: `No module named 'mcp.server.fastmcp'` | `mcp` 2.x was installed | `pip install 'mcp<2'` |
| Everything gone after restarting Operit | proot processes die with the app | `.bashrc` hook / `mcp-start` |
| Self-heal hook stops working after the first failure | A stale lock directory — a killed process never cleaned it up | Switched to `flock`, which is released with the process |
| The launcher runs on every shell start for no reason | A deleted service is still listed in the hook's port list | Keep the port list in sync with `SERVICES` |
| `GET /` returns 404, looks dead | The endpoint only answers `POST /mcp` | Probe with `POST /mcp` |

### Evaluated and dropped

| Project | Why |
|---|---|
| conport | 4.6GB venv on its own (vector store / embeddings); the disk can't take it |
| thesisagent | Same class of heavy dependencies |
| scholar_mcp | go-sdk wants Go ≥ 1.23, the local toolchain is 1.22 and the download is blocked; no prebuilt release either |
| arxiv-mcp (anuj0456) | The code is a stub — `run_server()` literally says "Server implementation would go here" |

## License

MIT
