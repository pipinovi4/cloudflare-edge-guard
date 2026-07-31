SHELL := /usr/bin/env bash
SCRIPTS := edge-guard.sh scripts/update_cf_edge.sh $(wildcard lib/*.sh)

.PHONY: test syntax lint format format-check check
test:
	bats tests
syntax:
	bash -n $(SCRIPTS)
lint:
	shellcheck $(SCRIPTS)
format:
	shfmt -w -i 4 -ci $(SCRIPTS) tests/*.bats tests/test_helper.bash
format-check:
	shfmt -d -i 4 -ci $(SCRIPTS) tests/*.bats tests/test_helper.bash
check: syntax lint format-check test
