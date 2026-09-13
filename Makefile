SHELL := /bin/bash
.DEFAULT_GOAL := help

APP_NAME := UsageBar
APP_DIR := dist/$(APP_NAME).app
BINARY := usagebar
BUILD_ARGS := -c release --arch arm64
FORMAT_PATHS := Sources Tests Package.swift
INSTALL_DIR := /Applications/$(APP_NAME).app

.PHONY: help test lint format-check format build install

help: ## Show available commands
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z0-9_-]+:.*## / {printf "%-18s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

test: ## Run tests
	swift test

lint: ## Treat compiler warnings as errors
	swift build -Xswiftc -warnings-as-errors

format-check: ## Check Swift formatting
	swift format lint --strict --recursive $(FORMAT_PATHS)

format: ## Apply Swift formatting
	swift format --in-place --recursive $(FORMAT_PATHS)

build: ## Build an arm64 release app
	swift build $(BUILD_ARGS)
	@set -euo pipefail; \
	bin_path="$$(swift build $(BUILD_ARGS) --show-bin-path)"; \
	rm -rf "$(APP_DIR)"; \
	mkdir -p "$(APP_DIR)/Contents/MacOS" "$(APP_DIR)/Contents/Resources"; \
	cp "$$bin_path/$(BINARY)" "$(APP_DIR)/Contents/MacOS/$(BINARY)"; \
	cp Support/Info.plist "$(APP_DIR)/Contents/Info.plist"; \
	if [[ -n "$(USAGEBAR_VERSION)" ]]; then \
		/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(USAGEBAR_VERSION)" "$(APP_DIR)/Contents/Info.plist"; \
		/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(USAGEBAR_VERSION)" "$(APP_DIR)/Contents/Info.plist"; \
	fi; \
	codesign --force --sign - --timestamp=none "$(APP_DIR)"; \
	printf '%s\n' "$(CURDIR)/$(APP_DIR)"

install: build ## Build and install into /Applications
	-osascript -e 'quit app "$(APP_NAME)"' 2>/dev/null
	rm -rf "$(INSTALL_DIR)"
	cp -R "$(APP_DIR)" /Applications/
	open "$(INSTALL_DIR)"
	@printf '%s\n' "$(INSTALL_DIR)"
