# 国际化契约

默认使用 Flutter `flutter_localizations` + ARB + `gen-l10n`。App 拥有业务文案和语言偏好；`koi_ui` 拥有组件通用文案与可复用的语言匹配算法。domain/data 不依赖 `BuildContext` 或生成的 UI 翻译类；错误通过类型或错误码交给展示层翻译。

## 配置与运行时

- 各成员的 `l10n.yaml` 指定输入 ARB、英文模板和 `lib/l10n/generated` 输出。`pubspec.yaml` 开启 `flutter.generate`。生成文件不手改、不入库。
- `lib/l10n/app_locale_policy.dart` 是每个 App 的运行时策略入口：支持语言从生成的 `AppLocalizations.supportedLocales` 读取；App 明确选择 `fallbackLocale`，维护语言自称 `nativeNames`。
- 语言选择器、偏好反序列化、MaterialApp 的支持列表与匹配回调都消费同一个 `appLocalePolicy`。新增 ARB 后无需在 provider 或选择器另写 switch；新语言的名称未配置时显示其语言标签。
- 宿主同时注册 `KoiUiLocalizations.delegate` 和 `AppLocalizations.localizationsDelegates`。共享组件允许显式传入业务文案，不反向依赖 App。
- `locale == null` 表示持续跟随系统，不把当时解析出的设备语言持久化。用户选择语言后保存 `Locale.toLanguageTag()`；读取兼容旧的下划线标签，未知或已移除语言回到跟随系统。
- 精确 locale 优先；中文显式 `Hans/Hant` 优先于地区。没有脚本时，TW/HK/MO 推断为 Hant，其他中文请求默认 Hans；只有通用 `zh` 时使用它作中文回退。请求列表均无法匹配时使用 App 的 fallback。

蓝图当前英／简／繁三种语言为 `en`、`zh`、`zh_Hant`；默认 fallback 为 `zh`。英文模板决定消息接口，fallback 决定不支持的系统语言显示哪一种，两者独立。更改 fallback 时，设置页说明会使用该语言的名称。

minimal 默认使用内存偏好，设置页面及其存储按需安装；workbench 使用 Native JSON / Web localStorage。切换语言只重建展示，保持 router、工作区会话和编辑状态的拥有者稳定。管理端认证演示仍是固定中文宿主，不代表新模板的完整国际化接入。

## 原生资源与诊断网页

创建器通过 `tool/platform_localization.py` 为 iOS/macOS 同步 `CFBundleLocalizations` 和 Xcode `knownRegions`，使用系统语言标签 `en`、`zh-Hans`、`zh-Hant`。安装默认诊断能力时，三语 `InfoPlist.strings` 通过 Runner 的资源构建阶段打包，翻译局域网权限说明；系统提示使用 OS 为 App 选择的语言，不由 Dart 页面语言直接改写。已有翻译或工程接线有冲突时保留用户文件并报告需合并，不静默覆盖。

诊断共享文案位于 `koi_diagnostics` 的 `DiagnosticStrings`，设备页面、Android 前台服务通知和 LAN 网页共用词表。LAN 启动时使用当前页面语言，停止后重启可应用新语言；网页标题、`lang` 和导出错误均与所选译文一致。Android 宿主的 `koi/diagnostics` 通道更新已有通知渠道名称，保留渠道 ID、重要性和用户设置；升级诊断包时须同时采用能力配方的 MainActivity 接线。原始日志、协议字段和 HTTP 状态码保留诊断原文。

ARB 门禁只覆盖 ARB 源；原生打包资源、诊断共享词表和网页脚本由 Python、Dart 与 Chrome 行为回归分别验证。目标 OS 的系统弹窗、通知和语言偏好仍需真实运行验收，详见 [平台验收](../platform-acceptance.md)。

## 新增与翻译文案

1. 在模板 ARB 中增加语义明确的 key，并提供 `@key.description`，说明出现位置、动作含义和易混淆词。
2. 同步所有翻译文件。翻译完整句子，不拼接需要改变语序的片段；原始错误诊断与用户可读消息分开。
3. 参数放进 `placeholders`，明确 `type`，补充有代表性的 `example`。数量使用 ICU plural/select；日期与数字使用生成器的格式选项或显式 locale 的 intl 格式器，不用固定格式代替本地化。业务币种、时区须由业务配置决定。
4. 能力配方的英文元数据和翻译要与受测样例同步，否则安装合并时会报告冲突。
5. 执行 `python3 blueprint.py check generate`，再验证实际页面。

安装能力时，`capability add` 按 ARB 顶层 key 合并。项目自定义的标题、译文和项目独有的 key 会保留，配方新增的 key 会补入。首次安装使用 schema 2 的 App 文件基线，同版本、同配置重装时使用上次安装的配方快照。只有配方改动的值会更新，双方改成相同值也可以继续。配方移除的 key 留给 App。消息和对应的 `@key` 各自比较，整份占位符元数据算作一个值。

多个能力共用一个 key 时，配方声明的值须一致，项目可以保留自己的译文。同一 key 改成不同值，或新配方需要项目已删除的 key 时，安装会在写入前报告 ARB 路径和 key。可先用 `capability add ID --app PATH --dry-run` 核对，解决冲突后再安装。旧安装记录只有摘要时，工具会在工程和蓝图源码中查找与摘要一致的配方原文。历史内容缺失时，先从项目历史恢复相应基线或参照文件，再重新规划。

```json
{
  "@@locale": "en",
  "documentCount": "{count, plural, =1{1 document} other{{count} documents}}",
  "@documentCount": {
    "description": "Number of documents in the current workspace sidebar.",
    "placeholders": {"count": {"type": "int", "example": "3"}}
  }
}
```

## 检查与测试

`python3 blueprint.py check l10n` 只读检查活动成员的 ARB：键与模板一致、没有空字符串或重复 JSON 键、locale 与文件名一致、元数据没有孤立键、已声明的占位符有类型和翻译说明、译文中的占位符元数据与模板一致。翻译文件可省略元数据并继承模板。

检查读取源文件，不信任可能过期的 `.dart_tool/untranslated_messages.json`。完整 ICU 语法和参数使用由 Flutter `gen-l10n` 验证；`check l10n` 单独通过不等于完整生成通过。该源检查已接入 `generate` / `generate-check`，因此进入 `validate` 和 CI，也在创建项目、安装能力的 staging 中执行。

测试至少覆盖：设备语言匹配（包括脚本与地区冲突）、显式选择覆盖系统、恢复跟随系统、偏好恢复与失效、切换后 router/session 身份保留，以及英／简／繁在窄屏和 200% 字号下的选择交互。增加 RTL 语言时使用 `EdgeInsetsDirectional` / `AlignmentDirectional` 等方向布局并补对应测试；现有三种语言的测试不证明 RTL 已验收。

创建器目前仍要求完整的三种受测语言。扩展或裁剪创建器语言范围时，同时更新 `tool/blueprint_config.py` 的受测集合、配方翻译和生成回归；不要仅放宽配置校验。

参考：[Flutter 国际化](https://docs.flutter.dev/ui/internationalization)、[Locale 匹配](https://api.flutter.dev/flutter/widgets/WidgetsApp/supportedLocales.html)、[VGV 国际化实践](https://engineering.verygood.ventures/development/internationalization/localization/)。
