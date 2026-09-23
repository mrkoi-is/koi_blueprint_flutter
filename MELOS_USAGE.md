# Melos Usage

## 常用命令

```bash
export PATH="$PWD/tool:$PATH"
./tool/dartw pub get
./tool/melos bootstrap
./tool/melos run format:check --no-select
./scripts/check_generated.sh
./tool/melos run analyze --no-select
./tool/melos run test --no-select
./tool/melos run coverage --no-select
./tool/melos run precommit --no-select
./scripts/validate_workspace.sh
```

## Makefile 包装

```bash
make bootstrap
make format-check
make generate-check
make analyze
make test
make coverage
make precommit
make validate
```

## 说明

- `.fvmrc` 固定 Flutter 3.47.2；CI 同样校验该版本
- wrapper 依次使用显式 `*_BIN`、项目 FVM、FVM 命令，最后才回退到 PATH
- `format:check` 不会改写文件；生成物不入库，`generate-check` 验证 `melos run generate` 可完整运行
- `validate_workspace.sh` 与 CI 共用，包含严格锁文件、代码生成、格式、分析、测试、Web 构建和覆盖率
