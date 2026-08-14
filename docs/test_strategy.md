# Test Strategy

## 分层建议

- `packages/koi_core`：纯单元测试
- `packages/koi_auth`：认证状态与敏感字段脱敏测试
- `packages/koi_domain`：实体与序列化测试
- `packages/koi_ui`：Widget 测试
- `packages/koi_api_bootstrap`：token、401、平台后端与安全配置测试
- `apps/*`：页面、Provider、路由与集成冒烟测试

## 默认门禁

- `format:check`
- `generate`（生成物不入库，验证代码生成可完整运行）
- `analyze --fatal-infos`
- 全 Workspace `test`
- 排除生成文件后的手写代码合并行覆盖率 ≥ 60%
- 含可执行逻辑的手写源码必须出现在覆盖率报告；入口与 Web 条件实现由 release/JS 构建验证

## Blueprint 当前覆盖

- 6/6 Workspace 成员均有测试
- App 覆盖认证成功/失败/并发取消、Router 稳定性和登录重定向
- Package 覆盖 401 合并处理、安全日志、序列化失败与共享 UI
- `scripts/check_coverage.sh` 在本地和 CI 使用同一统计口径
