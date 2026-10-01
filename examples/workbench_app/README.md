# Koi Workbench

这是 `--template workbench` 的受测生成源。一个工作区会话持有文本资料、媒体素材、待办和后台任务，三个视图通过稳定的类型化 `StatefulShellRoute.indexedStack` 导航。

## 创建与运行

在蓝图根目录运行：

```sh
python3 blueprint.py create acme --output ../acme --org com.example --template workbench
cd ../acme
python3 blueprint.py validate
cd apps/acme_app
flutter run -d macos
```

`examples/workbench_app` 保存业务源码、测试和小型真实媒体 fixture，平台 runner 由固定 Flutter SDK 生成。可以用 `--platforms web,macos` 创建平台子集；Linux 需要 `libmpv-dev`、`mpv`、`libepoxy-dev` 及 Flutter 的 GTK 构建依赖。

## 行为与资源归属

- 文本：新建、导入 UTF-8 TXT/Markdown、重命名、搜索、纯文本编辑；停止输入 500ms 自动保存，显式保存立即提交。
- 素材：导入 JPEG/PNG/MP4 工作区副本、图片缩放、视频播放/暂停/seek/音量、实际缩略图；首次打开视频后生成首帧缩略图。
- 任务：待办与后台导入/缩略图任务使用不同模型；可取消与重试，重试保留原记录。
- 导航：64px 固定图标栏，底部设置可切换主题和密度；窄窗口将设置移到顶部。macOS 使用原生统一工具栏：红黄绿右侧同一行放后退、前进、项目标题，保存固定右侧；宽窗口去掉重复 Flutter 标题区，与导航背景同步。
- 页面历史：顶部后退/前进恢复视图和资料/素材选择，保留草稿与播放器；历史仅限本次会话，最多 100 条，跳过已删除内容。后退后打开新内容清空前进分支，保存和任务进度不增加历史。Cmd+[ / Cmd+]；非 macOS 另支持 Alt+Left / Alt+Right。
- Native：应用管理目录内的串行快照、暂存、备份与恢复。Web：IndexedDB 元数据和实际 Blob；预览 URL 不进入持久化模型。
- 导入上限默认文本 256 KiB、图片 20 MiB、视频 100 MiB；验收视频为 MP4/H.264 8-bit 4:2:0/AAC-LC。
- 应用会话拥有任务，展示会话拥有播放器与预览源，bootstrap 最后关闭存储。插件选择器由用户关闭；废弃迟到结果不会替代关闭原生对话框。

这些工作台依赖不会进入默认 `minimal` 模板。`domain` 不包含插件、文件句柄、浏览器对象、播放器类型或 Blob URL。

取消会等待不能中断的存储操作返回：若取消发生在元数据保存期间，先持久化回滚，再删除新素材；回滚保存失败时保留仍被引用的字节，显示可重试的失败。若新缩略图已保存、正在清理旧图，则保留新图，清理完成后才报告取消。

## 验证

```sh
python3 blueprint.py validate
python3 blueprint.py check browser
# 以下在生成项目的 App 目录执行：
flutter test --no-pub -d macos integration_test/workbench_runtime_test.dart
chromedriver --port=4444
# 在另一个终端执行：
flutter drive --no-pub --driver integration_test/support/runtime_driver.dart --target integration_test/workbench_runtime_test.dart -d web-server --headless --driver-port=4444 --web-browser-flag=--autoplay-policy=no-user-gesture-required
```

浏览器测试实际验证 IndexedDB、Blob、URL 释放和图片生成。集成 fixture 测试使用真实存储、播放器和截图 API，文件选择入口使用 fixture adapter，不能证明系统文件对话框已验收。ChromeDriver 版本需要与本地 Chrome 兼容；Safari WebDriver 需要已启用远程自动化，测试不会替用户修改该设置。

`assets/fixtures/manifest.json` 保存固定 fixture 的编码、尺寸和哈希；`tool/create_media_fixtures.py` 是可选重新生成工具，普通测试不要求 FFmpeg。VM 覆盖率未采集的浏览器实现按零命中纳入分母，浏览器真实运行单独报告。
