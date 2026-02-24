# Docker 镜像构建约定（01_ 成本透视真实数据）

> [TRACEBACK] 实践: [01_成本透视真实数据](../../lighthouse-doc/04_阶段规划与实践/Phase4_真实环境集成与交付/01_成本透视真实数据.md) §4.2

## 唯一权威位置与命名

本目录为**前后端 Dockerfile 的唯一存放位置**，避免与源码仓根目录混淆。

| 文件 | 用途 | 构建上下文 |
|------|------|------------|
| **Dockerfile.backend** | 后端 API 服务镜像 | `lighthouse-src`（Makefile / compose 从上级指定） |
| **Dockerfile.frontend** | 前端 SPA 镜像（nginx） | `lighthouse-src/web` |
| **nginx-frontend.conf** | 前端 nginx 配置（SPA、/api 代理、/build-info、安全头） | 构建时从 `lighthouse-src/web/docker/` 拷贝（见 Dockerfile.frontend） |

- **lighthouse-src** 下不保留无名 `Dockerfile`，构建统一通过 `make docker-all`（使用本目录 Dockerfile）或 `docker compose build`。
- 镜像 tag 规则：`lighthouse-backend:$(VERSION)-$(GIT_COMMIT)`、`lighthouse-frontend:$(VERSION)-$(GIT_COMMIT)` 及 `:latest`。
