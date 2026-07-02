# ZenStats Deploy

One-command Docker Compose deployment for the full ZenStats stack. Supports both **local development** and **production deployment**.

## Architecture

```
                     ┌─────────────────────────────┐
 Internet ────▶ [Caddy :80/:443]                   │
                     │  ghcr.io/zenstats/zenstats-web
                     │  SPA + Tracker JS + API proxy │
                     └──────────┬──────────────────┘
                                │ /api/* reverse proxy
                                ▼
                     ┌─────────────────────────────┐
                     │ zenstats :8080               │
                     │  ghcr.io/zenstats/zenstats   │
                     │  Go API backend               │
                     └──────┬──────────┬───────────┘
                            │          │
                            ▼          ▼
                   ┌──────────┐  ┌──────────────┐
                   │ PG :5432 │  │ CH :9000/8123 │
                   │ postgres │  │  clickhouse   │
                   └──────────┘  └──────────────┘
```

## Prerequisites

| Tool | Version | Check |
|------|---------|-------|
| **Docker** | ≥ 24.0 | `docker --version` |
| **Docker Compose** | ≥ 2.0 | `docker compose version` |
| **Go** (local builds) | ≥ 1.25 | `go version` |
| **Node.js + pnpm** (frontend local dev) | ≥ 22 | `node --version` |

---

## Local Development (one-command start)

Clone all three repos as siblings, then start everything with a single command:

```bash
git clone https://github.com/zenstats/zenstats.git ../zenstats
git clone https://github.com/zenstats/zenstats-web.git ../zenstats-web
git clone https://github.com/zenstats/zenstats-deploy.git
cd zenstats-deploy

make local
```

This automatically:
1. Creates `.env` from `.env.local` template (ready to go)
2. Starts PostgreSQL + ClickHouse
3. Builds the API from local source and starts it
4. Builds the frontend from `../zenstats-web` source and starts the Caddy gateway

After startup:

| URL | Description |
|-----|-------------|
| **http://localhost** | Admin dashboard |
| http://localhost:8080/api/health | API health check |
| localhost:5433 | PostgreSQL (host direct) |
| localhost:9001 | ClickHouse Native |
| localhost:8124 | ClickHouse HTTP |

### Common Commands

```bash
make local          # One-command start
make local-down     # Stop and clean data
make local-logs     # View all service logs
make local-ps       # View service status
make local-build    # Rebuild after API code changes
make local-reset    # Full reset (clean data + rebuild)
make seed-test      # Generate 3 days of test data (deterministic, ~200 events)
make seed           # Generate 30 days of simulated data
```

### Frontend Hot-Reload Development

For frequent frontend changes, run the Vite dev server on the host (with hot reload) instead of using the Docker frontend:

```bash
# Terminal 1: Start backend (databases + API)
make db-up

# Terminal 2: Start frontend dev server
make frontend-dev     # equivalent: cd ../zenstats-web && pnpm install && pnpm dev
```

Navigate to `http://localhost:5173`. API requests auto-proxy to `localhost:8080`.

### Database-Only Mode (IDE debugging)

To run the API on the host for IDE breakpoint debugging, start only the databases:

```bash
make db-up

# Then run the API manually in the zenstats directory:
cd ../zenstats
go run main.go migrate
go run main.go server       # → http://localhost:8080
```

Database ports are mapped to `localhost:5433` (PG) and `localhost:9001` (CH), matching the embedded default config.

### Port Mapping Reference

| Service | Container Port | Host Port | Notes |
|---------|---------------|-----------|-------|
| Caddy | 80, 443 | 80, 443 | Frontend gateway |
| API | 8080 | 8080 | Go backend |
| PostgreSQL | 5432 | **5433** | Avoids host PG conflicts |
| ClickHouse Native | 9000 | **9001** | Matches default config |
| ClickHouse HTTP | 8123 | **8124** | Browser access |

---

## Production Deployment

```bash
git clone https://github.com/zenstats/zenstats-deploy.git
cd zenstats-deploy

# 1. Configure
cp .env.example .env
vi .env   # Set domain, secret key, etc.

# 2. Start
make prod     # or: docker compose up -d

# 3. Access
open https://your-domain.com
```

On first startup: database migration and GeoIP download (~40MB) run automatically.

### Production Commands

```bash
make prod         # Start
make prod-down    # Stop
make prod-logs    # View logs
```

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `ZENSTATS_SECRET_KEY` | **production** | — | JWT signing key; empty = startup failure in production |
| `ZENSTATS_DOMAIN` | No | `localhost` | Domain (non-localhost enables auto SSL) |
| `DB_PASSWORD` | Recommended | `postgres` | Database password |
| `ZENSTATS_MAXMIND_LICENSE_KEY` | No | — | MaxMind GeoIP key (free registration; leave empty for fallback) |
| `IMAGE_ZENSTATS` | No | `ghcr.io/zenstats/zenstats:latest` | API image |
| `IMAGE_FRONTEND` | No | `ghcr.io/zenstats/zenstats-web:latest` | Frontend image |

> **Local dev**: Copy `.env.local` — uses all defaults.
> **Production**: Copy `.env.example` — must set `ZENSTATS_DOMAIN` and `ZENSTATS_SECRET_KEY`.

Full variable reference: [docs/DEPLOY.md](docs/DEPLOY.md).

## Project Structure

```
zenstats-deploy/
├── docker-compose.yml          # Production (pre-built images)
├── docker-compose.local.yml    # Local dev (API local build + port exposure)
├── docker-compose.dev.yml      # Legacy dev overlay (API local build only)
├── docker-compose.test.yml     # Integration tests (isolated PG + CH, tmpfs)
├── .env.example                # Production env template
├── .env.local                  # Local dev env template (ready to go)
├── Makefile                    # Convenience commands (local / db / prod / test)
├── clickhouse/                 # ClickHouse config
│   ├── logs.xml
│   ├── ipv4-only.xml
│   └── low-resources.xml
└── docs/
    ├── DEPLOY.md               # Detailed deployment guide
    └── architecture.md         # System architecture overview
```

## Container Images

| Image | Registry | Architectures |
|-------|----------|---------------|
| API Backend | `ghcr.io/zenstats/zenstats` | amd64, arm64 |
| Frontend Gateway | `ghcr.io/zenstats/zenstats-web` | amd64, arm64 |

Both repos build multi-arch images via Gitea Actions on push.

## Documentation

- [Deployment Guide](docs/DEPLOY.md)
- [Architecture](docs/architecture.md)
- [API Project](https://github.com/zenstats/zenstats) ↗
- [Frontend Project](https://github.com/zenstats/zenstats-web) ↗

---

## License

**AGPL-3.0** — See [LICENSE.md](LICENSE.md) for details.
