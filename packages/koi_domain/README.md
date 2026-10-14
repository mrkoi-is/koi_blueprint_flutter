# koi_domain

认证样例使用的纯 Dart 用户契约包，按需接入；默认 minimal/workbench 不依赖它。公开入口 [koi_domain.dart](lib/koi_domain.dart) 仅导出 KoiUser，字段为 id/name/companyCode/role。

KoiUser 支持不可变 copyWith、snake_case JSON 和 displayName；tryFromJson 返回 koi_core 的 Result，反序列化失败保持 serialization 错误。业务 repository 与 IO 不放在这里。未公开的历史展示模型不属于当前公共 API。

根目录 bootstrap/generate-check 后，本目录 `../../tool/flutterw test --no-pub`。测试覆盖正确 JSON、缺失字段及错误类型；不要用 model 测试替代真实 API 验收。
