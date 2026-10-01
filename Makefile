.DEFAULT_GOAL := help
PYTHON ?= python3
.PHONY: bootstrap format-check generate generate-check analyze test coverage validate precommit help
bootstrap:
	$(PYTHON) blueprint.py check bootstrap
format-check generate-check analyze test coverage:
	$(PYTHON) blueprint.py check $@
generate:
	$(PYTHON) blueprint.py check generate
validate precommit:
	$(PYTHON) blueprint.py validate
help:
	@$(PYTHON) blueprint.py --help
