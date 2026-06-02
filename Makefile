.DEFAULT_GOAL := help

DART := ./tool/dartw
MELOS := PATH="$(PWD)/tool:$$PATH" $(DART) run melos

bootstrap: ## 初始化 workspace 依赖
	$(DART) pub get
	$(MELOS) bootstrap

generate: ## 运行代码生成
	$(MELOS) run generate --no-select

analyze: ## 分析全部 package 和 app
	$(MELOS) run analyze --no-select

test: ## 运行全部测试
	$(MELOS) run test --no-select

precommit: ## 格式 + 分析 + 测试
	$(MELOS) run precommit --no-select

help: ## 显示帮助
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "%-15s %s\\n", $$1, $$2}'
