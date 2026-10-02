# 平台构建与真实运行验收

两种模板、六端均分别记录生成、构建、实际运行；CI产物绑定源码摘要和runner。CI配置不代表当前工作树已通过。源码完整validate和递归生成另列。每个平台使用匹配SDK的主机和真实可用设备。

## 本轮能力适用性（运行前固定）

| 能力 | macOS / Windows / Linux | Android / iOS | Web |
| --- | --- | --- | --- |
| 国际化、界面、诊断、分页、网络、缓存 | 实际运行 | 实际运行 | 真实浏览器运行 |
| 数据库与资料存储 | Native 持久化 | Native 持久化 | 验证浏览器持久后端，内存回退不计通过 |
| 资料索引 | 授权目录递归 | 授权资料范围 | 用户选择的资料范围 |
| 窗口、托盘、桌面 mini | 实际运行 | 不适用 | 不适用 |
| 系统媒体 | OS adapter | 通知、锁屏和音频会话 | 页面存活期间的浏览器媒体控制 |
| 主屏组件 | 不适用 | 原生组件实际添加与回调 | 不适用 |
| 外部入口 | URI、文件、启动参数 | URI、文件、分享 | URL 路由和文件输入 |
| 局域网协作 | 服务端与控制端 | 前台控制端 | 手工地址配对控制端 |

每条记录使用 `PASS`、`FAIL`、`NOT_RUN`、`NOT_APPLICABLE`；设备或签名缺席只能记 `NOT_RUN`，不能在运行失败后改适用性。能力测试、生成工程测试、OS 实际运行分别计量。

## 可复跑命令

```sh
python3 tool/platform_evidence.py --output /tmp/koi-platform-source.json
python3 blueprint.py create acceptance --output ../acceptance --org com.example --template workbench
cd ../acceptance
python3 blueprint.py doctor --purpose run
python3 blueprint.py devices
python3 blueprint.py run --app apps/acceptance_app --device macos
python3 blueprint.py build --app apps/acceptance_app --platforms web,macos
```

设备ID按devices结果替换。Android/iOS实际运行需连接设备或启动模拟器，不用APK/IPA构建代替。Windows/Linux须在相应主机运行；Linux需要GTK和文档列出的媒体依赖。

运行集成fixture测试：在App目录用同一固定SDK执行 `flutter test --no-pub -d <设备ID> integration_test/workbench_runtime_test.dart`。它验证真实存储和媒体，但选择文件由fixture替代。

Web：使用匹配浏览器版本的ChromeDriver或SafariDriver，按照workbench README的drive入口运行。Safari另需已开启远程自动化及可用SafariDriver；缺少时记NOT_RUN，不自动修改用户系统设置。Chrome测试结果不能替代Safari结果。

## 人工流程

每个平台用隔离工作区及固定JPEG/PNG/MP4测试文件：

1. 使用系统文件选择器导入中文TXT/Markdown、图片和视频；取消一次选择。
2. 编辑后立即正常关闭，重开验证中文、待办、偏好与素材恢复。
3. 同一工作区打开第二实例/标签页：提示占用；关闭第一实例后重试进入。
4. 播放、暂停、seek、音量、首次缩略图；切换视图与resize保持会话和位置。
5. 窄窗口、明暗主题、200%字号，设置/侧栏/详情入口可达。
6. 保存失败时退出应取消，保留可编辑内容；强杀恢复单独登记，不承诺退出前异步保存。

证据保存OS/设备/浏览器版本、源码摘要、生成参数、命令日志、产物SHA256及运行结果；未执行写NOT_RUN，失败记录原始错误。VoiceOver/TalkBack/Narrator和真实文件对话框单列，fixture不折算为人工流程通过。
