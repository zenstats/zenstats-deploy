# ZenStats 部署指南

## 目录

- [架构概览](#架构概览)
- [快速开始](#快速开始)
- [本地开发](#本地开发)
- [生产部署](#生产部署)
- [手动部署](#手动部署)
- [环境变量](#环境变量)
- [升级与维护](#升级与维护)
- [常见问题](#常见问题)

---

## 架构概览

ZenStats 由三个独立仓库组成，通过 Docker Compose 编排部署：

```
┌─────────────────────────────────────────────────────┐
│                  Docker Compose                      │
│                                                      │
│  ┌──────────────┐   ┌──────────────┐                 │
│  │   frontend   │   │   zenstats   │                 │
│  │  Caddy :443  │──▶│   Go :8080   │                 │
│  │  SPA+Tracker │   │   API 后端    │                 │
│  └──────────────┘   └──────┬───────┘                 │
│                            │                         │
│              ┌─────────────┴─────────────┐           │
│              ▼                           ▼           │
│     ┌────────────────┐     ┌────────────────────┐    │
│     │  zenstats_db   │     │ zenstats_events_db │    │
│     │  PostgreSQL 18 │     │  ClickHouse 25.11  │    │
│     └────────────────┘     └────────────────────┘    │
└─────────────────────────────────────────────────────┘
```

| 仓库 | 镜像 | 说明 |
|------|------|------|
| [zenstats](https://github.com/zenstats/zenstats) | `ghcr.io/zenstats/zenstats` | Go API 后端 |
| [zenstats-web](https://github.com/zenstats/zenstats-web) | `ghcr.io/zenstats/zenstats-web` | Caddy + React SPA + Tracker JS |

镜像支持 `linux/amd64` 和 `linux/arm64`，Docker 自动选择匹配架构。

---

## 快速开始

### 1. 克隆部署项目

```bash
git clone https://github.com/zenstats/zenstats-deploy.git
cd zenstats-deploy
```

### 2. 配置环境变量

```bash
cp .env.example .env
vi .env
```

**最小配置**（其余使用默认值）：

```bash
ZENSTATS_SECRET_KEY=$(openssl rand -base64 32)   # 必填，留空生产启动失败
ZENSTATS_DOMAIN=stats.example.com                # 你的域名
DB_PASSWORD=your_secure_password
ZENSTATS_MAXMIND_LICENSE_KEY=your_key_here       # 可选，免费注册: https://dev.maxmind.com
```

### 3. 启动

```bash
docker compose up -d
```

首次启动会自动：数据库迁移、GeoIP 数据库下载（~40MB，仅一次）。

### 4. 访问

- 管理面板：`https://stats.example.com`
- 埋点脚本：`https://stats.example.com/js/script.js`
- API 健康检查：`https://stats.example.com/api/health`（综合）/ `/api/health/live`（存活）/ `/api/health/ready`（就绪，含数据库）

> 使用 `localhost` 域名时 Caddy 使用自签名证书，浏览器需手动信任。

---

## 本地开发

### 一键启动全栈（推荐）

将三个仓库 clone 到同级目录，一条命令启动：

```bash
# 目录结构要求:
# ~/projects/
#   ├── zenstats/          (API 后端)
#   ├── zenstats-web/      (前端面板)
#   └── zenstats-deploy/   (部署配置，当前目录)

git clone https://github.com/zenstats/zenstats.git ../zenstats
git clone https://github.com/zenstats/zenstats-web.git ../zenstats-web
git clone https://github.com/zenstats/zenstats-deploy.git
cd zenstats-deploy

make local
```

这会自动：
1. 从 `.env.local` 创建 `.env`（全部默认值，开箱即用）
2. 启动 PostgreSQL + ClickHouse 容器
3. 从本地 `../zenstats` 源码构建 API 镜像并启动
4. 从本地 `../zenstats-web` 源码构建前端，启动 Caddy 网关

启动后访问 **http://localhost** 即可看到完整的管理面板。

### 开发模式选择

| 模式 | 命令 | 适用场景 |
|------|------|----------|
| **全栈 Docker** | `make local` | 快速预览、前后端联调 |
| **仅数据库 + 宿主机 API** | `make db-up` + 手动 `go run` | IDE 断点调试、频繁改 API |
| **仅数据库 + 前端热重载** | `make db-up` + `make frontend-dev` | 频繁改前端 UI |
| **Mock 前端（零依赖）** | `cd ../zenstats-web && VITE_USE_MOCK=true pnpm dev` | 纯前端开发，无需后端 |

### 常用命令

```bash
make local          # 一键启动全栈
make local-down     # 停止并清理数据卷
make local-logs     # 实时查看所有服务日志
make local-ps       # 查看服务运行状态
make local-build    # 修改 API 代码后重新构建并重启
make local-reset    # 完全重置（清理 + 重建）
make seed-test      # 生成 3 天测试数据
make seed           # 生成 30 天全量仿真数据

make db-up          # 仅启动数据库（PG + CH）
make db-down        # 停止数据库
make frontend-dev   # 启动前端 Vite 开发服务器（热重载）
```

### 端口映射

本地开发环境端口映射（宿主机 ← 容器）：

| 服务 | 宿主机端口 | 容器端口 | 说明 |
|------|-----------|----------|------|
| Caddy 网关 | 80, 443 | 80, 443 | 前端 + API 代理 |
| API 后端 | 8080 | 8080 | 调试接口 |
| PostgreSQL | **5433** | 5432 | 避免与宿主机 PG 冲突 |
| ClickHouse Native | **9001** | 9000 | 与默认配置一致 |
| ClickHouse HTTP | **8124** | 8123 | 浏览器访问 |

> 宿主机端口映射与嵌入式默认配置完全对齐，无需额外配置。

### 使用预构建前端镜像（可选，加速启动）

默认 `make local` 从本地源码构建前端（首次约 3-5 分钟）。如需加速：

1. 编辑 `docker-compose.local.yml`，注释 `build` 并取消 `image` 注释
2. 运行 `make local`

或直接使用 `make frontend-dev` 在宿主机运行 Vite 开发服务器（推荐，支持热重载）。

### 修改 API 后如何生效

```bash
# 方式 1: 重新构建 API 镜像（全栈 Docker 模式）
make local-build

# 方式 2: 宿主机直接运行（仅数据库模式）
make db-up
cd ../zenstats && go run main.go server
```

### 修改前端后如何生效

```bash
# 方式 1: Vite 热重载（推荐）
make frontend-dev     # 保存代码即刷新

# 方式 2: 重新构建前端 Docker 镜像
make frontend-build
docker compose -f docker-compose.yml -f docker-compose.local.yml up -d frontend
```

### 环境变量

本地开发使用 `.env.local` 模板，全部默认值即可：

```bash
# 查看当前配置
cat .env

# 如需自定义（如使用远程数据库）:
vi .env
```

---

## 生产部署

### 固定镜像版本

生产环境建议在 `.env` 中固定镜像版本，避免 `latest` 意外更新：

```bash
IMAGE_ZENSTATS=ghcr.io/zenstats/zenstats:v1.0.0
IMAGE_FRONTEND=ghcr.io/zenstats/zenstats-web:v1.0.0
```

### 自动更新

使用 [watchtower](https://containrrr.dev/watchtower/) 自动更新镜像：

```bash
# docker-compose.yml 中添加
  watchtower:
    image: containrrr/watchtower
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    command: --interval 3600 zenstats frontend
```

### SSL 证书

Caddy 自动通过 Let's Encrypt 申请和续期 SSL 证书。

- 域名必须正确解析到服务器 IP
- 80/443 端口必须可公网访问

### 备份

```bash
# PostgreSQL
docker compose exec zenstats_db pg_dump -U postgres zenstats > backup.sql

# ClickHouse（停机备份数据卷）
docker compose stop zenstats_events_db
mkdir -p ./backups
docker compose run --rm \
  -v "$(pwd)/backups":/backup \
  --entrypoint sh \
  zenstats_events_db \
  -c "tar czf /backup/clickhouse-$(date +%Y%m%d).tar.gz -C /var/lib/clickhouse ."
docker compose start zenstats_events_db
```

### 数据持久化

数据卷由 Docker 管理：

| 卷 | 内容 |
|------|------|
| `db-data` | PostgreSQL 数据 |
| `event-data` | ClickHouse 事件数据 |
| `event-logs` | ClickHouse 日志 |
| `zenstats-data` | GeoIP 数据库、应用缓存 |

---

## 手动部署

不依赖 Docker，直接运行 Go 二进制。

### 环境要求

- Go 1.25+
- PostgreSQL 18+
- ClickHouse 25.11+

### 步骤

```bash
git clone https://github.com/zenstats/zenstats.git
cd zenstats

# 配置
export APP_ENV=prod
export ZENSTATS_DB_HOST=localhost
export ZENSTATS_DB_PASSWORD=your_password
export ZENSTATS_CLICKHOUSE_ADDR=localhost:9000
export ZENSTATS_MAXMIND_LICENSE_KEY=your_key

# 构建 & 迁移
make build
./bin/zenstats migrate

# 启动（监听 0.0.0.0:8080）
./bin/zenstats server
```

前端需单独部署 Nginx/Caddy 代理静态文件 + 反向代理 API。

---

## 环境变量

所有变量可通过 `ZENSTATS_` 前缀覆盖 YAML 配置。完整列表：

| 变量 | 必填 | 默认 | 说明 |
|------|------|------|------|
| `ZENSTATS_SECRET_KEY` | **生产必填** | — | JWT 签名密钥，留空生产环境启动失败 |
| `ZENSTATS_MAXMIND_LICENSE_KEY` | 否 | — | MaxMind GeoIP Key（免费注册，留空降级使用 Loyalsoldier 数据） |
| `ZENSTATS_DOMAIN` | 否 | `localhost` | 部署域名 |
| `DB_PASSWORD` | 建议修改 | `postgres` | 数据库密码 |
| `IMAGE_ZENSTATS` | 否 | `ghcr.io/zenstats/zenstats:latest` | API 镜像 |
| `IMAGE_FRONTEND` | 否 | `ghcr.io/zenstats/zenstats-web:latest` | 前端镜像 |
| `APP_ENV` | 否 | `prod` | 运行环境 |
| `GIN_MODE` | 否 | `release` | Gin 模式 |
| `ZENSTATS_DB_HOST` | 否 | `zenstats_db` | PG 主机 |
| `ZENSTATS_DB_PORT` | 否 | `5432` | PG 端口 |
| `ZENSTATS_DB_USERNAME` | 否 | `postgres` | PG 用户 |
| `ZENSTATS_DB_DATABASE` | 否 | `zenstats` | PG 库名 |
| `ZENSTATS_CLICKHOUSE_ADDR` | 否 | `zenstats_events_db:9000` | CH 地址 |
| `ZENSTATS_CLICKHOUSE_USERNAME` | 否 | `default` | CH 用户 |
| `ZENSTATS_CLICKHOUSE_PASSWORD` | 否 | — | CH 密码 |
| `ZENSTATS_LOG_LEVEL` | 否 | `info` | 日志级别 |
| `ZENSTATS_POOL_SIZE` | 否 | `100` | 事件协程池 |
| `ZENSTATS_SCHEME_HTTP_PORT` | 否 | `8080` | HTTP 端口 |
| `ZENSTATS_SMTP_HOST` | 否 | — | SMTP 主机 |
| `ZENSTATS_SMTP_PORT` | 否 | `587` | SMTP 端口 |
| `ZENSTATS_SMTP_USERNAME` | 否 | — | SMTP 用户 |
| `ZENSTATS_SMTP_PASSWORD` | 否 | — | SMTP 密码 |
| `ZENSTATS_SMTP_FROM` | 否 | — | 发件人地址 |

---

## 升级与维护

### 升级镜像

```bash
docker compose pull        # 拉取 latest 或指定版本
docker compose up -d       # 滚动重启
```

### 数据库迁移

容器启动时自动执行（`entrypoint.sh`），无需手动操作。

手动执行：

```bash
docker compose exec zenstats /app/zenstats migrate
```

### 日志

```bash
docker compose logs -f zenstats        # API 日志
docker compose logs -f frontend        # Caddy 访问日志
docker compose logs -f                 # 全部日志
```

---

## 常见问题

### GeoIP 下载失败

- 确保配置了 `ZENSTATS_MAXMIND_LICENSE_KEY`
- 未配置时会自动使用 Loyalsoldier/geoip 免费数据库（精度略低）
- 数据库首次下载 ~40MB，仅下载一次，持久化在 volume 中

### ClickHouse IPv6 错误

```
Address family for hostname not supported
```

Docker 默认不支持 IPv6。`clickhouse/ipv4-only.xml` 已内置修复此问题。

### 国内构建慢

```bash
docker compose build --build-arg APK_MIRROR=mirrors.aliyun.com
```

### 查看 API 文档

```bash
# 在 API 仓库
go run main.go doc
open http://localhost:8081/swagger/index.html
```

### 镜像拉取失败

确保已登录 GitHub Container Registry：

```bash
echo $GHCR_TOKEN | docker login ghcr.io -u your_username --password-stdin
```

公开镜像无需登录。
