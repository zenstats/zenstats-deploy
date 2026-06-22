# ZenStats Deploy

Docker Compose 一键部署 ZenStats 全栈服务，支持**本地开发**和**生产部署**两种模式。

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

## 前置要求

| 工具 | 版本 | 检查 |
|------|------|------|
| **Docker** | ≥ 24.0 | `docker --version` |
| **Docker Compose** | ≥ 2.0 | `docker compose version` |
| **Go**（本地构建时） | ≥ 1.24 | `go version` |
| **Node.js + pnpm**（前端本地开发时） | ≥ 22 | `node --version` |

---

## 本地开发（一键启动）

将三个仓库 clone 到同级目录，一条命令启动全栈：

```bash
git clone https://git.potawang.cn/zenstats/zenstats.git ../zenstats
git clone https://git.potawang.cn/zenstats/zenstats-web.git ../zenstats-web
git clone https://git.potawang.cn/zenstats/zenstats-deploy.git
cd zenstats-deploy

make local
```

这会自动：
1. 创建 `.env`（从 `.env.local` 模板，开箱即用）
2. 启动 PostgreSQL + ClickHouse
3. 从本地源码构建 API 并启动
4. 从本地 `../zenstats-web` 源码构建前端并启动 Caddy 网关

启动后访问：

| 地址 | 说明 |
|------|------|
| **http://localhost** | 管理面板 |
| http://localhost:8080/api/health | API 健康检查 |
| localhost:5433 | PostgreSQL（宿主机直连） |
| localhost:9001 | ClickHouse Native |
| localhost:8124 | ClickHouse HTTP |

### 常用命令

```bash
make local          # 一键启动
make local-down     # 停止并清理数据
make local-logs     # 查看所有服务日志
make local-ps       # 查看服务状态
make local-build    # 修改 API 代码后重新构建
make local-reset    # 完全重置（清理数据 + 重建）
make seed-test      # 生成 3 天测试数据（确定性，~200 事件）
make seed           # 生成 30 天全量仿真数据
```

### 前端热重载开发

如果需要频繁修改前端代码，建议在宿主机运行 Vite 开发服务器（支持热重载），而非使用 Docker 内的前端：

```bash
# 终端 1: 启动后端（数据库 + API）
make db-up

# 终端 2: 启动前端开发服务器
make frontend-dev     # 等价于: cd ../zenstats-web && pnpm install && pnpm dev
```

访问 `http://localhost:5173`，API 请求自动代理到 `localhost:8080`。

### 仅数据库模式（IDE 断点调试）

如果需要在宿主机运行 API（方便 IDE 断点调试），只需启动数据库：

```bash
make db-up

# 然后在 zenstats 目录手动运行 API:
cd ../zenstats
go run main.go migrate
go run main.go server       # → http://localhost:8080
```

数据库端口已映射为 `localhost:5433`（PG）和 `localhost:9001`（CH），与 `config_dev.yaml` 一致。

### 端口映射参考

| 服务 | 容器内端口 | 宿主机端口 | 说明 |
|------|-----------|-----------|------|
| Caddy | 80, 443 | 80, 443 | 前端网关 |
| API | 8080 | 8080 | Go 后端 |
| PostgreSQL | 5432 | **5433** | 避免与宿主机 PG 冲突 |
| ClickHouse Native | 9000 | **9001** | 与 config_dev.yaml 一致 |
| ClickHouse HTTP | 8123 | **8124** | 浏览器访问 |

---

## 生产部署

```bash
git clone https://git.potawang.cn/zenstats/zenstats-deploy.git
cd zenstats-deploy

# 1. 配置
cp .env.example .env
vi .env   # 填入域名、密钥等

# 2. 启动
make prod     # 或 docker compose up -d

# 3. 访问
open https://your-domain.com
```

首次启动自动完成：数据库迁移、GeoIP 下载（~40MB）。

### 生产命令

```bash
make prod         # 启动
make prod-down    # 停止
make prod-logs    # 查看日志
```

## 环境变量

| 变量 | 必填 | 默认 | 说明 |
|------|------|------|------|
| `ZENSTATS_MAXMIND_LICENSE_KEY` | 否 | — | MaxMind GeoIP Key（免费注册或留空） |
| `ZENSTATS_DOMAIN` | 否 | `localhost` | 域名（非 localhost 自动 SSL） |
| `ZENSTATS_SECRET_KEY` | 建议 | — | JWT 签名密钥 |
| `DB_PASSWORD` | 建议 | `postgres` | 数据库密码 |
| `IMAGE_ZENSTATS` | 否 | `ghcr.io/zenstats/zenstats:latest` | API 镜像 |
| `IMAGE_FRONTEND` | 否 | `ghcr.io/zenstats/zenstats-web:latest` | 前端镜像 |

> **本地开发**: 复制 `.env.local` 即可，全部使用默认值。  
> **生产部署**: 复制 `.env.example`，必须修改 `ZENSTATS_DOMAIN` 和 `ZENSTATS_SECRET_KEY`。

完整变量列表见 [docs/DEPLOY.md](docs/DEPLOY.md)。

## 项目结构

```
zenstats-deploy/
├── docker-compose.yml          # 生产部署（拉取预构建镜像）
├── docker-compose.local.yml    # 本地开发（API 本地构建 + 端口暴露）
├── docker-compose.dev.yml      # 旧版开发覆盖（仅 API 本地构建）
├── docker-compose.test.yml     # 集成测试（独立 PG + CH，tmpfs）
├── .env.example                # 生产环境变量模板
├── .env.local                  # 本地开发环境变量模板（开箱即用）
├── Makefile                    # 便捷命令（local / db / prod / test）
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
- [API 项目](https://git.potawang.cn/zenstats/zenstats) ↗
- [前端项目](https://git.potawang.cn/zenstats/zenstats-web) ↗

---

## License

**AGPL-3.0** — See [LICENSE.md](LICENSE.md) for details.
