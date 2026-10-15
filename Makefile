.PHONY: test lint

test: lint
	bats tests

lint:
	shellcheck voice-input
