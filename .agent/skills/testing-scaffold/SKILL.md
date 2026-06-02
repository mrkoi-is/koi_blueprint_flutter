---
name: testing-scaffold
description: 为 Provider、Widget、共享包补齐测试
---

1. 纯逻辑优先写单测
2. 页面交互写 Widget 测试
3. Provider 变化至少覆盖成功与失败两条路径
4. 新增测试后跑 `test`
