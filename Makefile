# Pi Web Desktop (macOS) — developer entry points.
#
# `make help` lists every target (the `##` comments below are grepped).
SHELL := /bin/bash
.DEFAULT_GOAL := help

APP        := build/PiWeb.app
BIN        := $(APP)/Contents/MacOS/PiWeb
INSTALLED  := /Applications/PiWeb.app
LOG_FILE   := $(HOME)/Library/Logs/PiWeb/pi-web.log

.PHONY: help build run install uninstall verify clean version log

help: ## Show this help
	@echo "Pi Web Desktop (macOS) — available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| sort \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

build: ## Build build/PiWeb.app with swiftc
	./build.sh

run: build ## Build and launch the app
	open "$(APP)"

install: build ## Copy the app to /Applications and re-register it
	./scripts/install.sh

uninstall: ## Remove /Applications/PiWeb.app
	@if [ -d "$(INSTALLED)" ]; then \
		rm -rf "$(INSTALLED)"; \
		echo "Removed $(INSTALLED)"; \
	else \
		echo "$(INSTALLED) is not installed"; \
	fi
	@osascript -e 'tell application "Pi Web" to quit' >/dev/null 2>&1 || true

verify: ## Run the headless verification suite (scripts/verify.sh)
	./scripts/verify.sh

clean: ## Delete the build/ directory
	rm -rf build
	@echo "Removed build/"

version: ## Print the version the built app reports
	@if [ -x "$(BIN)" ]; then \
		"$(BIN)" --version; \
	else \
		echo "not built yet; run 'make build' first" >&2; \
		exit 1; \
	fi

log: ## Tail the app log
	@mkdir -p "$$(dirname "$(LOG_FILE)")"; \
	touch "$(LOG_FILE)"; \
	tail -f "$(LOG_FILE)"
