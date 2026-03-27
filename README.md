# lighthouse-deploy

本地与集群部署资产；**一键 compose** 与 **Helm Umbrella** 变量键应对齐。

| 资产 | 说明 |
|------|------|
| [docker-compose.yml](docker-compose.yml) | 本地全栈（postgres / backend / frontend / 可选 clickhouse profile） |
| [.env.example](.env.example) | 环境变量键名权威；K8s Secret/values 映射时保持一致 |
| [charts/lighthouse-stack](charts/lighthouse-stack) | **lighthouse-stack** Umbrella Chart（Bitnami **PostgreSQL / Redis / ClickHouse** + 可选 OpenCost）；子 Chart **vendoring** 见下表 |
| [scripts/local-build-and-verify.sh](scripts/local-build-and-verify.sh) | 构建与验收 |
| [scripts/vendor-helm-dependencies.sh](scripts/vendor-helm-dependencies.sh) | `helm dependency update`，生成/更新 `charts/lighthouse-stack/charts/*.tgz` |

### Helm 子 Chart 本地打包（防网络拉包失败）

- **路径**：`charts/lighthouse-stack/charts/` 下的 `postgresql-*.tgz`、`redis-*.tgz`、`clickhouse-*.tgz`、`opencost-*.tgz` 由 `helm dependency update` 生成，与 **`Chart.lock`** 版本一致。
- **更新依赖后**：在 **lighthouse-deploy** 根目录执行 `./scripts/vendor-helm-dependencies.sh`（或 `cd charts/lighthouse-stack && helm dependency update`），将新生成的 **tgz + Chart.lock** 一并提交，部署机即可不访问 Bitnami/OpenCost Helm 仓库。
- **说明**：Umbrella 的 `Chart.yaml` **dependencies** 仍保留 `repository` 字段；Helm 会优先使用本地 `charts/*.tgz`。

### GitOps 密钥（Sealed Secrets）

- **不在本 Chart 内嵌** Sealed Secrets controller；集群侧单独安装。
- **SOP（安装、kubeseal、禁止项、轮换）**：[Sealed_Secrets_GitOps密钥管理_SOP.md](../lighthouse-doc/04_阶段规划与实践/Phase4_真实环境集成与交付/Sealed_Secrets_GitOps密钥管理_SOP.md)

**设计文档（1:1:1）**：[08_一键部署工作流_设计.md](../lighthouse-doc/03_原子目标与协议/Phase4_真实环境集成与交付/08_一键部署工作流_设计.md) · OpenCost 子 Chart 细节：[Phase6 02_成本钻取与OpenCost集成_设计.md](../lighthouse-doc/03_原子目标与协议/Phase6_重大重构与演进/02_成本钻取与OpenCost集成/02_成本钻取与OpenCost集成_设计.md)
