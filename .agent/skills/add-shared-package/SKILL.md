---
name: add-shared-package
description: 新增共享 package，并保持 app 与 package 的依赖边界清晰
---

1. 共享能力优先放 `packages/`
2. package 不允许 import app 代码
3. 尽量把 package 设计成低耦合、可复用、可测试
4. 需要代码生成时同步配置 `build_runner`
5. 修改后至少验证 `analyze`
