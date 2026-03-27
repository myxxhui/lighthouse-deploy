# UAT 无数据排查与修复

## 根因（经日志确认）

UAT 云账单 API 调用返回 **NotAuthorized**，触发熔断后无法写入月表：

```
Code: NotAuthorized
Message: You are not authorized to call the API operation. Please check whether RAM user has the permission or check whether ownerId and callerId have been given the appropriate permission.
HostId: business.aliyuncs.com
```

**结论**：UAT 使用的 RAM 子账号（AuthPrincipalOwnerId: 1657988574642393）**未被授予 BSS 账单 API 权限**。

## 排查步骤

1. **查看 backend 日志**：
   ```bash
   podman logs lighthouse-deploy_backend_1 2>&1 | grep -E "fetch failed|NotAuthorized|step4 fetch month failed"
   ```
2. 若出现 `Code: NotAuthorized` → **RAM 权限不足**（见下）
3. 若出现 `error="cloud billing circuit open"` → 为熔断，根因在之前的 `fetch failed` 日志中

## 修复方案

### 方案 A：为 UAT RAM 子账号授予 BSS 只读权限（推荐）

在阿里云 RAM 控制台，为 UAT 对应的 RAM 用户附加策略：

- **AliyunBSSReadOnlyAccess**（账单只读）
- 或 **AliyunBSSFullAccess**（账单完全访问，如需更多能力）

路径：**RAM 控制台 → 用户 → 选择 UAT 对应用户 → 权限管理 → 添加权限 → 选择上述策略**。

授权后等待数分钟生效，重启 backend 并等待 ETL 完成：
```bash
docker compose restart backend
```

### 方案 B：endpoint 与凭证区域不匹配

若 UAT 为国际站账号但配置了中国站 endpoint，会报 InvalidAccessKeyId 等。此时可注释 `CLOUD_BILLING_ENDPOINT_UAT` 使 UAT 使用默认国际站 endpoint。

### 方案 C：仅 POC 有数据

若 UAT 无 BSS 数据需求，可不配置 UAT AK/SK 或从 `cost_env_account_config` 中移除 UAT。
