.PHONY: local local-up local-down local-reset local-build local-logs local-ps \
        db-up db-down db-reset \
        seed seed-test \
        prod prod-up prod-down prod-logs \
        test-up test-down \
        frontend-build frontend-dev

# ============================================================================
#  本地开发（一键启动全栈）
# ============================================================================

# 一键启动本地开发环境
local: local-up

# 启动全栈开发环境（前后端均从本地源码构建）
local-up:
	@cp -n .env.local .env 2>/dev/null || true
	@docker compose -f docker-compose.yml -f docker-compose.local.yml down 2>/dev/null || true
	@docker compose -f docker-compose.yml -f docker-compose.local.yml up -d --build
	@echo ""
	@echo "========================================"
	@echo "  ZenStats 本地环境已启动"
	@echo "========================================"
	@echo "  管理面板:    http://localhost"
	@echo "  API 健康检查: http://localhost:8080/api/health"
	@echo "  PostgreSQL:  localhost:5433"
	@echo "  ClickHouse:  localhost:9001 (native) / localhost:8124 (http)"
	@echo ""
	@echo "  生成数据: make seed-test     # 3天测试数据"
	@echo "           make seed           # 30天仿真数据"
	@echo "  停止:     make local-down"
	@echo "========================================"

# 停止并清理本地环境
local-down:
	@docker compose -f docker-compose.yml -f docker-compose.local.yml down -v
	@echo "本地环境已停止，数据卷已清理。"

# 重建 API 镜像（代码修改后）
local-build:
	@docker compose -f docker-compose.yml -f docker-compose.local.yml build --no-cache zenstats
	@docker compose -f docker-compose.yml -f docker-compose.local.yml up -d zenstats
	@echo "API 已重新构建并重启。"

# 重置本地环境（清理所有数据 + 重建）
local-reset: local-down local-up
	@echo "本地环境已完全重置。"

# 查看本地环境日志
local-logs:
	@docker compose -f docker-compose.yml -f docker-compose.local.yml logs -f

# 查看本地环境状态
local-ps:
	@docker compose -f docker-compose.yml -f docker-compose.local.yml ps

# ============================================================================
#  前端本地开发（宿主机 pnpm dev，热重载）
# ============================================================================

# 启动前端开发服务器（需先 make local-up 启动后端）
frontend-dev:
	@cd ../zenstats-web && pnpm install && pnpm dev

# 本地构建前端 Docker 镜像（用于全栈 docker 环境）
frontend-build:
	@docker compose -f docker-compose.yml -f docker-compose.local.yml build --no-cache frontend
	@echo "前端镜像已构建。"

# ============================================================================
#  仅数据库（宿主机运行 API，IDE 断点调试）
# ============================================================================

# 启动数据库（不启动 API 和前端）
db-up:
	@docker compose -f docker-compose.yml -f docker-compose.local.yml up -d zenstats_db zenstats_events_db
	@echo ""
	@echo "========================================"
	@echo "  数据库已启动（API 需手动运行）"
	@echo "========================================"
	@echo "  PostgreSQL:  localhost:5433"
	@echo "  ClickHouse:  localhost:9001 (native)"
	@echo "  ClickHouse:  localhost:8124 (http)"
	@echo ""
	@echo "  启动 API:"
	@echo "    cd ../zenstats && go run main.go migrate && go run main.go server"
	@echo "  或使用 test 配置（与 test-up 端口一致）:"
	@echo "    cd ../zenstats && APP_ENV=test go run main.go migrate && APP_ENV=test go run main.go server"
	@echo "========================================"

# 停止数据库
db-down:
	@docker compose -f docker-compose.yml -f docker-compose.local.yml down -v
	@echo "数据库已停止，数据卷已清理。"

# 重置数据库
db-reset: db-down db-up
	@echo "数据库已重置。"

# ============================================================================
#  测试数据生成（需先 make local 或 make db-up）
# ============================================================================

# 生成测试数据（3 天确定性数据，~200 事件）
seed-test:
	@docker compose -f docker-compose.yml -f docker-compose.local.yml exec -e ZENSTATS_LOG_LEVEL=warn zenstats /app/zenstats seed --test --clean
	@echo "测试数据已生成（3 天，确定性随机种子=42）。"

# 生成全量仿真数据（30 天真实分布数据，含多维度 UA/Geo/UTM）
seed:
	@docker compose -f docker-compose.yml -f docker-compose.local.yml exec -e ZENSTATS_LOG_LEVEL=warn zenstats /app/zenstats seed --clean
	@echo "全量仿真数据已生成（30 天）。"

# ============================================================================
#  生产部署
# ============================================================================

prod: prod-up

prod-up:
	@test -f .env || (echo "ERROR: 请先 cp .env.example .env 并编辑配置" && exit 1)
	@docker compose up -d
	@echo "生产环境已启动。"

prod-down:
	@docker compose down
	@echo "生产环境已停止。"

# 生产环境本地构建前端镜像（使用 .env 中的 ZENSTATS_DOMAIN）
# 适用于需要自定义 VITE_DATA_DOMAIN 且无法等待 CI 重建的场景
prod-build:
	@test -f .env || (echo "ERROR: 请先 cp .env.example .env 并编辑配置" && exit 1)
	@echo "正在使用本地源码构建前端镜像（ZENSTATS_DOMAIN=$${ZENSTATS_DOMAIN:-localhost}）..."
	@docker compose -f docker-compose.yml -f docker-compose.local.yml build --no-cache frontend
	@echo ""
	@echo "前端镜像已构建完成。运行 make prod-up 重新部署。"
	@echo "注意：新镜像已支持运行时通过 ZENSTATS_DOMAIN 环境变量动态设置 data-domain。"

prod-logs:
	@docker compose logs -f

# ============================================================================
#  集成测试
# ============================================================================

test-up:
	@docker compose -f docker-compose.test.yml up -d --wait
	@echo ""
	@echo "测试数据库已启动:"
	@echo "  PostgreSQL: localhost:5433"
	@echo "  ClickHouse HTTP: http://localhost:8124"
	@echo "  ClickHouse Native: localhost:9001"

test-down:
	@docker compose -f docker-compose.test.yml down -v
	@echo "测试环境已清理。"
