# 最终验证

- 修改完成：14个源码、测试与规范文件，既有工作树保留；baseline.json与changes.json记录哈希，备份为.txt。
- 完整validate：PASS，退出0；手写覆盖率88.44%（3901/4411），目标80%，未扩大排除。
- 新增工具栏行为：5测试PASS；320/800/1440、200%字号、面板命令、控制器保持、详情按页面控制、底栏80+34安全区一次。
- 既有共享UI/布局定向：31测试PASS。工作台及原生桥接最终测试由完整validate覆盖并通过；早期失败日志保留诊断过程。
- 生成workbench：PASS，新隔离项目；全部koi_ui实现字节匹配最终源；main仅注入一次性中文夹具，未加入模板。
- macOS/Web release构建：PASS；macOS codesign --verify --deep --strict：PASS。
- macOS实际运行：PASS（限定范围），标题栏左右面板命令、抽屉、任务页隐藏详情、原生后退恢复文本；native-run.json和两张PNG。
- 底栏解释：标准Material3默认80，inset自动添加一次，未替换为iOS原生Tab Bar。
- 本轮NOT_RUN：其他OS真机、完整读屏宣布、Safari、新回退头栏的真实浏览器操作；Web构建不等于运行验收。
