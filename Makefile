.DEFAULT_GOAL := help
PYTHON ?= python3
.PHONY: bootstrap format format-check generate generate-check analyze test browser coverage architecture ai templates validate precommit help
bootstrap:
	$(PYTHON) blueprint.py check bootstrap
format format-check generate-check analyze test browser coverage architecture ai templates:
	$(PYTHON) blueprint.py check $@
generate:
	$(PYTHON) blueprint.py check generate
validate precommit:
	$(PYTHON) blueprint.py validate
help:
	@$(PYTHON) blueprint.py --help
