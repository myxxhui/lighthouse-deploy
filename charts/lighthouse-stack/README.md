# lighthouse-stack（Umbrella Chart，生产级）

[Ref: 03_Phase4/08_一键部署工作流_设计]

## 子 Chart（`helm dependency update`）

| 子 Chart | 用途 | 开关 |
| --- | --- | --- |
| **bitnami/postgresql** | 生产级 PostgreSQL（持久化、PDB、metrics、NetworkPolicy） | `postgresql.enabled` |
| **bitnami/redis** | 缓存/队列 | `redis.enabled` |
| **bitnami/clickhouse** | L3 证据平面（列式 OLAP；默认单机 `shards=1`、`keeper.enabled=false`） | `clickhouse.enabled` |
| **opencost** | 成本钻取 | `opencost.enabled` |

## Lighthouse 自有模板

- backend / frontend Deployment、Service、PDB、Ingress
- init-db **ConfigMap**（`{ReleaseName}-init-sql`），由 **`scripts/deploy.sh`** 绑定到 `postgresql.primary.initdb.scriptsConfigMap`

## 安装

```bash
cd ../../   # lighthouse-deploy 根目录
./scripts/deploy.sh -e dev    # 或 -e prod（需 envs/values-prod.yaml）
```

**必须**：`deploy.sh` 会执行 `--set-string postgresql.primary.initdb.scriptsConfigMap=${RELEASE_NAME}-init-sql`。若手写 `helm install`，须自行追加该 `--set-string`。

## 生产密钥

- 使用 `envs/values-prod.yaml` 中的 **`existingSecret`** 占位；在集群内创建 Secret 后再 `helm upgrade`。
- 勿将生产密码、AK/SK 提交到 Git。

## 与 docker-compose

- 键名对齐 `.env.example`；compose 使用 `postgres:15-alpine`，K8s 生产使用 **Bitnami PostgreSQL 镜像**，大版本升级需单独验证。
