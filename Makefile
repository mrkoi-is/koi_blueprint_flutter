.DEFAULT_GOAL := help

DART := ./tool/dartw
MELOS := PATH="$(CURDIR)/tool:$$PATH" ./tool/melos

.PHONY: bootstrap format-check generate generate-check analyze test coverage precommit help

bootstrap: ## 初始化 workspace 依赖
	$(DART) pub get
	$(MELOS) bootstrap

generate: ## 运行代码生成
	$(MELOS) run generate --no-select

generate-check: ## 运行代码生成（生成物不入库，验证可完整生成）
	./scripts/check_generated.sh

analyze: ## 分析全部 package 和 app
	$(MELOS) run analyze --no-select

format-check: ## 只读检查格式
	$(MELOS) run format:check --no-select

test: ## 运行全部测试
	$(MELOS) run test --no-select

coverage: ## 检查测试完整性与合并行覆盖率
	./scripts/check_coverage.sh

precommit: ## 格式 + 生成产物 + 分析 + 测试
	$(MELOS) run precommit --no-select

help: ## 显示帮助
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "%-15s %s\\n", $$1, $$2}'
