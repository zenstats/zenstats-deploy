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
│     │  PostgreSQL 16 │     │  ClickHouse 24.12  │    │
│     └────────────────┘     └────────────────────┘    │
└─────────────────────────────────────────────────────┘
```

| 仓库 | 镜像 | 说明 |
|------|------|------|
| [zenstats](https://git.potawang.cn/zenstats/zenstats) | `ghcr.io/zenstats/zenstats` | Go API 后端 |
| [zenstats-web](https://git.potawang.cn/zenstats/zenstats-web) | `ghcr.io/zenstats/zenstats-web` | Caddy + React SPA + Tracker JS |

镜像支持 `linux/amd64` 和 `linux/arm64`，Docker 自动选择匹配架构。

---

## 快速开始

### 1. 克隆部署项目

```bash
git clone https://git.potawang.cn/zenstats/zenstats-deploy.git
cd zenstats-deploy
```

### 2. 配置环境变量

```bash
cp .env.example .env
vi .env
```

**最小配置**（其余使用默认值）：

```bash
ZENSTATS_MAXMIND_LICENSE_KEY=your_key_here   # 免费注册: https://dev.maxmind.com
ZENSTATS_DOMAIN=stats.example.com            # 你的域名
ZENSTATS_SECRET_KEY=$(openssl rand -base64 32)
DB_PASSWORD=your_secure_password
```

### 3. 启动

```bash
docker compose up -d
```

首次启动会自动：数据库迁移、GeoIP 数据库下载（~40MB，仅一次）。

### 4. 访问

- 管理面板：`https://stats.example.com`
- 埋点脚本：`https://stats.example.com/js/script.js`
- API 健康检查：`https://stats.example.com/api/health`

> 使用 `localhost` 域名时 Caddy 使用自签名证书，浏览器需手动信任。

---

## 本地开发

将三个仓库 clone 到同级目录：

```bash
git clone https://git.potawang.cn/zenstats/zenstats.git ../zenstats
git clone https://git.potawang.cn/zenstats/zenstats-web.git ../zenstats-web
git clone https://git.potawang.cn/zenstats/zenstats-deploy.git
cd zenstats-deploy
```

启动开发环境（暴露数据库端口 + API 本地构建）：

```bash
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d --build
```

| 服务 | 端口 |
|------|------|
| Caddy 网关 | 80, 443 |
| API 后端 | 8080 |
| PostgreSQL | 5432 |
| ClickHouse HTTP | 8123 |
| ClickHouse Native | 9000 |

修改 API 代码后重新构建：

```bash
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d --build zenstats
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

- 确保障书邮箱：`ZENSTATS_ACME_EMAIL=admin@example.com`（可选）
- 域名必须正确解析到服务器 IP
- 80/443 端口必须可公网访问

### 备份

```bash
# PostgreSQL
docker compose exec zenstats_db pg_dump -U postgres zenstats > backup.sql

# ClickHouse
docker compose exec zenstats_events_db clickhouse-client --query "BACKUP DATABASE zenstats_events_db TO Disk('backups', 'backup.zip')"
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

- Go 1.24+
- PostgreSQL 16+
- ClickHouse 24.12+

### 步骤

```bash
git clone https://git.potawang.cn/zenstats/zenstats.git
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
| `ZENSTATS_MAXMIND_LICENSE_KEY` | 是 | — | MaxMind GeoIP Key（免费） |
| `ZENSTATS_DOMAIN` | 否 | `localhost` | 部署域名 |
| `ZENSTATS_SECRET_KEY` | 建议 | 自动生成 | JWT 签名密钥 |
| `DB_PASSWORD` | 是 | `postgres` | 数据库密码 |
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
