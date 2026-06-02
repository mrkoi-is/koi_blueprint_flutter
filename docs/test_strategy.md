# Test Strategy

## 分层建议

- `packages/koi_core`：纯单元测试
- `packages/koi_domain`：实体与序列化测试
- `packages/koi_ui`：Widget 测试
- `apps/*`：页面、Provider、路由与集成冒烟测试

## 默认门禁

- `generate`
- `analyze`
- `test`

## Blueprint 当前示例

- `packages/koi_core/test/app_failure_test.dart`
- `apps/koi_admin_app/test/app_test.dart`
