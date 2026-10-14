# Network Lab

独立可选网络样例：真实 HTTP 搜索、TTL/LRU 缓存、可取消流式下载、版本校验的 Range 恢复和前后台连通性提示。App/Provider 只装配 owner；domain 不依赖 Flutter、Dio 或浏览器 API。

- 搜索默认 300 ms 防抖，替换查询立即取消旧传输；服务端 opaque cursor 决定末页，合并稳定 ID，同游标请求合并，刷新保留旧内容并显示操作错误。
- 查询缓存默认 5 分钟、128 条、2 MiB，key 包含服务源、adapter 版本、owner scope 和请求 URI。失败不缓存；清理仅清本 owner 的派生数据。成功查询历史按最近使用去重，默认最多 20 条，只保留当前会话内存；`historyLimit: 0` 可关闭。
- Native 使用 Dio ResponseType.stream；Web 使用 Fetch ReadableStream + AbortController。Range 预取默认并发 3（可配置 1–8），范围默认 256 KiB（最大 8 MiB），总量上限 512 MiB。预取窗口含尚未写入的完整分块；按顺序验证写入，慢磁盘不会无限积压，非 Range 服务保持单流背压。
- 恢复必须匹配 URL、强 ETag 和总长度；每段必须满足 206/Content-Range/ETag/实际长度。源不支持 Range 时从零流式传输。完成后流式 SHA256，支持期望摘要校验，最后提交；网络中断保留暂存，主动取消等待清理后进入 cancelled。
- Native 暂存到应用支持目录，文件锁约束单 owner；Web 使用 IndexedDB 分块事务和 Web Locks，关闭后可重开恢复。已完成资产与暂存分离，取消不会删除旧完成资产。磁盘/浏览器 quota 和权限错误作为失败报告。
- 连通性只作提示；后台暂停探测，回到前台再探测，恢复仅重试幂等搜索；下载必须手动重试。`NetworkBootstrap.close()` 幂等等待任务清理，然后关 store/transport。

## 本地运行

在仓库根已统一 bootstrap/codegen 后：

```sh
python3 examples/network_lab/tool/http_fixture.py
cd examples/network_lab
../../tool/flutterw run -d chrome --dart-define=NETWORK_LAB_URL=http://127.0.0.1:8765/
```

App runner 由蓝图能力安装/平台配置阶段产生；源码提供完整 `main.dart`、typed router 和 bootstrap。实际设备地址应指向设备可达的受控测试服务。默认 loopback fixture 不接触个人文件，打印数据摘要和监听地址。

## 验证

```sh
cd examples/network_lab
../../tool/flutterw test --no-pub
../../tool/flutterw test --no-pub --platform chrome test/browser
python3 tool/run_http_smoke.py --flutter ../../tool/flutterw
```

最后一条自行启动临时端口 HTTP fixture，扫描已安装的 `test/http/*_http_test.dart`，并分别跑 VM 与 Chrome。network 配方独占共享 fixture/runner 与5个网络场景（包括页面填写服务地址后查询），images另加1个图片场景，互不覆盖。fixture图片内嵌，不依赖 images 资产。验证范围包括：真实分页、失败不缓存、2 MiB Range/普通流 SHA256、实际服务端断连计数、错误 ETag/Content-Range/短响应拒绝。普通成员测试明确跳过该 fixture 组；因此成员单测 PASS 不能替代真实 HTTP 冒烟。浏览器单测独立覆盖真实 Fetch 和 IndexedDB，无外部网络依赖。

当前宿主本地验证不替代 Windows/Linux/iOS/Android 设备验证。浏览器依赖 IndexedDB、Web Locks、Fetch streams 及允许这些 API 的运行上下文；缺少能力应显示启动失败，而不是声称已有持久化或传输成功。

## Images 可选能力

`features/images` 是独立功能，只有在选择 images 能力后接入宿主 registry；`buildImagesCapabilityPage` 不创建第二个 router。它和 Network 使用 `shared/network` 的可取消 HTTP 端口/适配器，但各自持有独立 transport、任务和缓存。两个页面通过宿主 `CapabilityLifecycle` 协调退出，prepare不释放资源；宿主允许退出后才close，普通离页也自行注销和清理。

来源类型是 Asset / Memory / Local reader / Network。页面可以直接切换来源，原生 Local 使用系统文件选择器，也允许输入路径；Web Local 通过浏览器文件选择器获取内容，Web从不把路径字符串当作可读文件。样例PNG位于 `assets/images/sample.png`，由本仓库生成。

网络图片缓存默认5分钟、32条、16MiB；单图编码上限8MiB、源像素上限16M；并发相同URL共用一次传输，取消一个观察者不取消其他人，最后一个观察者离开才中止底层请求。只有HTTP200且通过真实codec验证的图片才缓存；403/404、截断/损坏、超预算不会成为缓存成功。清理只影响当前图片owner，未完成请求也不能回填旧一代缓存。

当前验证格式为PNG/JPEG/GIF/WebP；先检查尺寸头，再实际解码，避免依赖Web不支持的ImageDescriptor尺寸API。UI显示布局dp、DPR、解码上限和实际像素，滑块控制目标尺寸，decode上限2048px，旧codec/image资源在替换和销毁时释放。网络错误显示重试按钮；有效缓存可在transport离线后读取，超过TTL必须重新请求。

图片行为测试包含真实Flutter codec、缓存离线命中与失败不缓存、并发请求引用计数取消、真实本地文件读取、页面Asset/Memory与DPR操作；Chrome同样运行真实codec和HTTP图片fixture。系统原生文件选择/设备安装仍需要相应目标平台交互验收。

网络/图片的翻译贡献位于 `l10n/network/` 与 `l10n/images/`，源 Lab 的 `lib/l10n/` 聚合两者供 gen-l10n。安装器通过 localizationSources 合并各能力的英/简/繁 ARB 到宿主，导航 titleKey 同步切换；维护时保持源 Lab 聚合 ARB 一致。网络能力页支持输入/提交服务地址，已有会话可进入设置后返回；不会默认连接公网。
