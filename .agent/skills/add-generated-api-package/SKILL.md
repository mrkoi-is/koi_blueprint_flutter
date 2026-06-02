---
name: add-generated-api-package
description: 接入 koi_swagger_parser 生成 API 包，并通过 koi_network 编排消费
---

1. 建立 `packages/<project>_api/` 作为纯生成产物
2. 建立 `packages/<project>_network/` 处理 envelope、adapter、request executor
3. App 只依赖 `<project>_network`，不要在页面层直接散落 Dio 逻辑
4. 生成后必须跑 `generate`、`analyze`
