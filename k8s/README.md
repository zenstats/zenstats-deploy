# ZenStats K8s 部署

## 目录结构

```
k8s/
├── namespace.yaml              # 命名空间 zenstats
├── configmap.yaml              # ClickHouse 配置 + Caddyfile + 应用配置
├── secret.yaml                 # 密钥（DB密码、JWT密钥、MaxMind Key）
├── postgresql/
│   ├── service.yaml            # Headless Service (ClusterIP: None)
│   └── statefulset.yaml        # StatefulSet (1 副本, postgres:18-alpine)
├── clickhouse/
│   ├── service.yaml            # ClusterIP (8123 HTTP, 9000 Native)
│   └── statefulset.yaml        # StatefulSet (1 副本, 25.11.5.8-alpine)
├── zenstats-api/
│   ├── pvc.yaml                # /app/data (GeoIP 数据库)
│   ├── service.yaml            # ClusterIP :8080
│   └── deployment.yaml         # Deployment + initContainers
├── frontend/
│   ├── service.yaml            # ClusterIP :80
│   └── deployment.yaml         # Caddy 静态文件 + 反向代理
├── ingress.yaml                # TLS Ingress (cert-manager)
└── kustomization.yaml          # Kustomize 编排
```

## 快速部署

### 1. 修改配置

编辑 `secret.yaml`，修改以下值：

```bash
# 生成随机密钥
openssl rand -base64 32   # → ZENSTATS_SECRET_KEY
openssl rand -base64 16   # → DB_PASSWORD
```

编辑 `configmap.yaml`，修改域名：

```yaml
# zenstats-config ConfigMap
data:
  ZENSTATS_DOMAIN: "stats.yourdomain.com"
```

编辑 `ingress.yaml`，修改域名和 IngressClass：

```yaml
spec:
  ingressClassName: nginx  # 你的 Ingress 控制器
  tls:
    - hosts:
        - stats.yourdomain.com
  rules:
    - host: stats.yourdomain.com
```

### 2. 安装 cert-manager（如未安装）

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml

# 创建 Let's Encrypt ClusterIssuer
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
            class: nginx
EOF
```

启用 Ingress 中的 cert-manager 注解：

```yaml
annotations:
  cert-manager.io/cluster-issuer: "letsencrypt-prod"
```

### 3. 部署

```bash
# 方式一：Kustomize（推荐）
kubectl apply -k zenstats-deploy/k8s/

# 方式二：逐个应用
kubectl apply -f zenstats-deploy/k8s/namespace.yaml
kubectl apply -f zenstats-deploy/k8s/configmap.yaml
kubectl apply -f zenstats-deploy/k8s/secret.yaml
kubectl apply -f zenstats-deploy/k8s/postgresql/
kubectl apply -f zenstats-deploy/k8s/clickhouse/
kubectl apply -f zenstats-deploy/k8s/zenstats-api/
kubectl apply -f zenstats-deploy/k8s/frontend/
kubectl apply -f zenstats-deploy/k8s/ingress.yaml
```

### 4. 验证

```bash
# 查看 Pod 状态
kubectl -n zenstats get pods -w

# 查看 API 日志
kubectl -n zenstats logs -l app.kubernetes.io/name=zenstats-api

# 端口转发测试
kubectl -n zenstats port-forward svc/zenstats-api 8080:8080
curl http://localhost:8080/api/health
```

## 生产环境建议

1. **固定镜像版本**：编辑 `kustomization.yaml`，使用 `images` 覆盖为具体版本
2. **StorageClass**：在 PVC 中添加 `storageClassName` 匹配集群配置
3. **资源限制**：根据实际负载调整 CPU/Memory requests/limits
4. **HPA**：为 API 和 Frontend 添加 HorizontalPodAutoscaler
5. **数据库备份**：配置 PostgreSQL 和 ClickHouse 的定期备份
6. **监控**：集成 Prometheus + Grafana 监控
