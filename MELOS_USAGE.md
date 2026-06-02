# Melos Usage

## 常用命令

```bash
export PATH="$PWD/tool:$PATH"
./tool/dartw pub get
./tool/dartw run melos bootstrap
./tool/dartw run melos run generate --no-select
./tool/dartw run melos run analyze --no-select
./tool/dartw run melos run test --no-select
./tool/dartw run melos run precommit --no-select
```

## Makefile 包装

```bash
make bootstrap
make generate
make analyze
make test
make precommit
```

## 说明

- `tool/dartw` / `tool/flutterw` 会优先读取 `DART_BIN` / `FLUTTER_BIN`
- 如果你的机器使用 FVM，也会尝试走 `fvm dart` / `fvm flutter`
