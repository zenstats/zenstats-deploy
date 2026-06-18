# ZenStats Deploy

Docker Compose 一键部署 ZenStats 全栈服务。

## 服务架构

```
                     ┌─────────────────────────────┐
 Internet ────▶ [Caddy :80/:443]                   │
                     │  ghcr.io/zenstats/zenstats-web
                     │  SPA + Tracker JS + API 代理  │
                     └──────────┬──────────────────┘
                                │ /api/* 反向代理
                                ▼
                     ┌─────────────────────────────┐
                     │ zenstats :8080               │
                     │  ghcr.io/zenstats/zenstats   │
                     │  Go API 后端                  │
                     └──────┬──────────┬───────────┘
                            │          │
                            ▼          ▼
                   ┌──────────┐  ┌──────────────┐
                   │ PG :5432 │  │ CH :9000/8123 │
                   │ postgres │  │  clickhouse   │
                   └──────────┘  └──────────────┘
```

## 快速开始

```bash
git clone https://git.potawang.cn/zenstats/zenstats-deploy.git
cd zenstats-deploy

# 1. 配置
cp .env.example .env
vi .env   # 填入 ZENSTATS_MAXMIND_LICENSE_KEY 等

# 2. 启动
docker compose up -d

# 3. 访问
open https://your-domain.com
```

首次启动自动完成：数据库迁移、GeoIP 下载（~40MB）。

## 本地开发

将 `zenstats` 仓库 clone 到同级目录，启动开发覆盖：

```bash
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d --build
```

`zenstats` 服务会从本地源码构建，代码修改即时生效。

## 环境变量

| 变量 | 必填 | 默认 | 说明 |
|------|------|------|------|
| `ZENSTATS_MAXMIND_LICENSE_KEY` | 是 | — | MaxMind GeoIP Key（免费注册） |
| `ZENSTATS_DOMAIN` | 否 | `localhost` | 域名（非 localhost 自动 SSL） |
| `ZENSTATS_SECRET_KEY` | 建议 | — | JWT 签名密钥 |
| `DB_PASSWORD` | 建议 | `postgres` | 数据库密码 |
| `IMAGE_ZENSTATS` | 否 | `ghcr.io/zenstats/zenstats:latest` | API 镜像 |
| `IMAGE_FRONTEND` | 否 | `ghcr.io/zenstats/zenstats-web:latest` | 前端镜像 |

完整列表见 [docs/DEPLOY.md](docs/DEPLOY.md)。

## 项目结构

```
zenstats-deploy/
├── docker-compose.yml          # 生产部署（拉取预构建镜像）
├── docker-compose.dev.yml      # 开发覆盖（本地构建 API）
├── docker-compose.test.yml     # 集成测试（独立 PG + CH）
├── .env.example                # 环境变量模板
├── clickhouse/                 # ClickHouse 配置
│   ├── logs.xml
│   ├── ipv4-only.xml
│   └── low-resources.xml
└── docs/
    ├── DEPLOY.md               # 详细部署指南
    └── architecture.md         # 系统架构说明
```

## 镜像仓库

| 镜像 | 地址 | 架构 |
|------|------|------|
| API 后端 | `ghcr.io/zenstats/zenstats` | amd64, arm64 |
| 前端网关 | `ghcr.io/zenstats/zenstats-web` | amd64, arm64 |

两个仓库通过 Gitea Actions 在 push 时自动构建多架构镜像。

## 文档

- [详细部署指南](docs/DEPLOY.md)
- [系统架构](docs/architecture.md)
- [API 文档](https://git.potawang.cn/zenstats/zenstats) ↗
- [前端项目](https://git.potawang.cn/zenstats/zenstats-web) ↗
