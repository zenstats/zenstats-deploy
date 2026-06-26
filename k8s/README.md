# ZenStats Kubernetes 部署

## 目录结构

```
k8s/
├── namespace.yaml              # 命名空间 zenstats
├── configmap.yaml              # ClickHouse 配置 + Caddyfile + 应用域名
├── secret.yaml                 # 密钥模板（开发/测试用，生产见下方说明）
├── kustomization.yaml          # Kustomize 编排入口
├── postgresql/
│   ├── service.yaml            # Headless Service（StatefulSet DNS 发现）
│   └── statefulset.yaml        # StatefulSet，postgres:18-alpine，10Gi PVC
├── clickhouse/
│   ├── service.yaml            # ClusterIP（8123 HTTP, 9000 Native）
│   └── statefulset.yaml        # StatefulSet，25.11.5.8-alpine，20Gi PVC
├── zenstats-api/
│   ├── pvc.yaml                # 1Gi PVC（GeoIP 数据库 ~40MB）
│   ├── service.yaml            # ClusterIP :8080
│   └── deployment.yaml         # Deployment + initContainers（等待 PG/CH 就绪）
├── frontend/
│   ├── service.yaml            # ClusterIP :80
│   └── deployment.yaml         # Caddy（静态文件 + API 反向代理）
└── ingress.yaml                # TLS Ingress → frontend（cert-manager）
```

## 流量路由

**所有外部流量经由 Ingress → Caddy（frontend:80）统一处理**，不要在 Ingress 中拆分 `/api` 直连后端：

```
外部请求
    │
    ▼
[Ingress]  (TLS 终止)
    │
    ▼
[Caddy frontend:80]
    ├── /js/*        → 静态文件（Tracker 脚本，含 CORS 头）
    ├── /api/event   → zenstats-api:8080（含 CORS 预检处理）
    ├── /api/*       → zenstats-api:8080
    └── /            → React SPA
```

> Tracker 脚本从第三方网站发起跨域请求到 `/api/event`，CORS 头由 Caddy 添加。
> 若 Ingress 将 `/api` 直连后端，CORS 头缺失，Tracker 采集会失败。

---

## 前置要求

- Kubernetes 1.28+
- kubectl（v1.14+ 已内置 kustomize）
- Ingress 控制器（Traefik / nginx 等）
- cert-manager 1.13+（自动 TLS，可选）

---

## 部署步骤

### 1. 修改域名

两处需要替换 `stats.example.com`：

**`configmap.yaml`**（应用域名）：
```yaml
data:
  ZENSTATS_DOMAIN: "stats.yourdomain.com"
```

**`ingress.yaml`**（Ingress 路由 + TLS）：
```yaml
spec:
  ingressClassName: traefik        # 改为你的 Ingress 控制器
  tls:
    - hosts:
        - stats.yourdomain.com
  rules:
    - host: stats.yourdomain.com
```

### 2. 管理密钥

> ⚠️ **不要将含有真实密钥的 `secret.yaml` 提交到 Git**

**方式一：secretGenerator（推荐，密钥文件不进 Git）**

```bash
# 生成密钥并写入 k8s/.env.secret（已在 .gitignore 中排除）
cat > k8s/.env.secret <<EOF
DB_PASSWORD=$(openssl rand -base64 16)
ZENSTATS_SECRET_KEY=$(openssl rand -base64 32)
ZENSTATS_MAXMIND_LICENSE_KEY=your_maxmind_key_here
EOF
```

然后编辑 `kustomization.yaml`：删除 `- secret.yaml`，取消注释 `secretGenerator` 块。

**方式二：kubectl 直接创建（不留文件）**

```bash
kubectl create secret generic zenstats-secrets \
  --from-literal=DB_PASSWORD="$(openssl rand -base64 16)" \
  --from-literal=ZENSTATS_SECRET_KEY="$(openssl rand -base64 32)" \
  --from-literal=ZENSTATS_MAXMIND_LICENSE_KEY="your_key" \
  -n zenstats
```

创建后从 `kustomization.yaml` 的 resources 中删除 `- secret.yaml`。

**方式三：直接修改 secret.yaml（仅开发/测试）**

编辑 `secret.yaml` 填入密钥，**不要提交此文件**：
```bash
git update-index --assume-unchanged k8s/secret.yaml
```

### 3. 安装 cert-manager（如未安装）

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml

# 等待 cert-manager 就绪
kubectl wait --namespace cert-manager \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s
```

创建 ClusterIssuer（`ingressClassName` 必须与 `ingress.yaml` 中 `spec.ingressClassName` 一致）：

```bash
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - http01:
          ingress:
            ingressClassName: traefik    # ← 与 ingress.yaml 保持一致
EOF
```

### 4. 部署

```bash
# Kustomize 一键部署（推荐）
kubectl apply -k k8s/

# 或按依赖顺序逐个应用
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/secret.yaml
kubectl apply -f k8s/postgresql/
kubectl apply -f k8s/clickhouse/
kubectl apply -f k8s/zenstats-api/
kubectl apply -f k8s/frontend/
kubectl apply -f k8s/ingress.yaml
```

### 5. 验证

```bash
# 查看所有 Pod 状态（等待全部 Running）
kubectl -n zenstats get pods -w

# 检查 TLS 证书状态
kubectl -n zenstats get certificate

# 端口转发测试 API
kubectl -n zenstats port-forward svc/zenstats-api 8080:8080
curl http://localhost:8080/api/health

# 查看 API 日志
kubectl -n zenstats logs -l app.kubernetes.io/name=zenstats-api -f
```

---

## 升级

```bash
# 更新配置后重新应用
kubectl apply -k k8s/

# 等待滚动升级完成
kubectl -n zenstats rollout status deployment/zenstats-api
kubectl -n zenstats rollout status deployment/frontend

# 回滚（如需要）
kubectl -n zenstats rollout undo deployment/zenstats-api
```

固定镜像版本（生产建议）：取消注释 `kustomization.yaml` 中的 `images` 块并填写版本号。

---

## 生产建议

| 项目 | 说明 |
|------|------|
| **固定镜像版本** | 取消注释 `kustomization.yaml` 中 `images` 字段，指定 `v1.0.0` 等具体版本 |
| **StorageClass** | 在 `volumeClaimTemplates` 中添加 `storageClassName` 匹配集群存储 |
| **Secret 管理** | 生产建议使用 Sealed Secrets 或 External Secrets Operator |
| **资源调优** | 按实际负载调整各服务的 `requests`/`limits` |
| **数据库备份** | PostgreSQL: `pg_dump`；ClickHouse: 参考 `docs/DEPLOY.md` |
| **HPA** | 为 `zenstats-api` 和 `frontend` 添加 HorizontalPodAutoscaler |
| **监控** | 集成 Prometheus + Grafana（API 暴露 `/api/health` 端点） |

---

## 常见问题

**TLS 证书长时间 Pending**

```bash
kubectl -n zenstats describe certificate zenstats-tls
kubectl describe clusterissuer letsencrypt-prod
```

检查：① cert-manager ClusterIssuer 的 `ingressClassName` 与 Ingress 一致；② 域名已解析到集群 IP；③ 80 端口可从公网访问（ACME HTTP-01 验证需要）。

**Pod 卡在 Init 阶段**

```bash
kubectl -n zenstats describe pod <pod-name>
kubectl -n zenstats logs <pod-name> -c wait-for-postgresql
kubectl -n zenstats logs <pod-name> -c wait-for-clickhouse
```

initContainer 等待数据库就绪，通常 30s 内完成。若持续失败，检查 PVC 是否绑定：
```bash
kubectl -n zenstats get pvc
```

**ClickHouse OOMKilled**

```bash
kubectl -n zenstats describe pod -l app.kubernetes.io/name=clickhouse
```

`low-resources.xml` 已限制 `max_threads=1`，适合 <2GB 节点。若仍 OOM，调高 StatefulSet 的 `resources.limits.memory`。

**Tracker 跨域请求失败（CORS 错误）**

检查 `ingress.yaml` 的 rules 是否只有 `path: /` 指向 `frontend:80`（不能有 `/api` 直连后端的规则）。查看当前配置：
```bash
kubectl -n zenstats get ingress zenstats -o yaml
```
