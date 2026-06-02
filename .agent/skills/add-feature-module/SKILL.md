---
name: add-feature-module
description: 按 Koi Flutter 目录规范新增业务 Feature
---

1. 在 `apps/<app>/lib/features/<feature>/` 下建立 `data/domain/presentation`
2. `data` 只放 datasource / repository 实现
3. `domain` 只放实体与 repository 抽象
4. `presentation` 只放 provider / screen / widget
5. Provider 命名和文件名保持 feature 前缀一致
6. 补最少一条 Provider 或 Widget 测试
