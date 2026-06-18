# ZenStats Deploy

Docker Compose 部署编排项目。

## 服务

| 服务 | 镜像 | 端口 |
|------|------|------|
| frontend | `ghcr.io/zenstats/zenstats-web:latest` | 80, 443 |
| zenstats | `${IMAGE_ZENSTATS:-ghcr.io/zenstats/zenstats:latest}` | 8080 (内部) |
| zenstats_db | `postgres:16-alpine` | 5432 (内部) |
| zenstats_events_db | `clickhouse/clickhouse-server:24.12-alpine` | 9000/8123 (内部) |

## 快速开始

```bash
git clone https://git.potawang.cn/zenstats/zenstats-deploy.git
cd zenstats-deploy

cp .env.example .env
# 编辑 .env 填入你的配置

docker compose up -d
```

## 本地开发

```bash
# 将 zenstats 仓库 clone 到同级目录，然后启动开发环境
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d --build
```

## 环境变量

| 变量 | 必填 | 说明 |
|------|------|------|
| `ZENSTATS_MAXMIND_LICENSE_KEY` | 是 | MaxMind GeoIP License Key |
| `ZENSTATS_DOMAIN` | 否 | 域名（默认 localhost 自签证书） |
| `ZENSTATS_SECRET_KEY` | 建议 | JWT 签名密钥 |
| `DB_PASSWORD` | 建议 | 数据库密码 |
| `IMAGE_ZENSTATS` | 否 | API 后端镜像 |
| `IMAGE_FRONTEND` | 否 | 前端镜像 |
