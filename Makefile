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
	is_ascii_alnum() { \
		case "$$1" in \
			[A-Za-z0-9]) return 0 ;; \
			*) return 1 ;; \
		esac; \
	}; \
	is_canonical_owner() { \
		local value="$$1"; \
		local size=$${#value}; \
		(( size >= 1 && size <= 39 )) || return 1; \
		local first="$${value:0:1}"; \
		local last="$${value:$$(($${#value} - 1)):1}"; \
		is_ascii_alnum "$$first" || return 1; \
		is_ascii_alnum "$$last" || return 1; \
		local previous_separator=0; \
		local char=""; \
		for ((i = 0; i < size; i++)); do \
			char="$${value:$$i:1}"; \
			if is_ascii_alnum "$$char"; then \
				previous_separator=0; \
				continue; \
			fi; \
			if [[ "$$char" == "-" ]]; then \
				if (( previous_separator == 1 )); then return 1; fi; \
				previous_separator=1; \
				continue; \
			fi; \
			return 1; \
		done; \
		return 0; \
	}; \
	is_canonical_repository() { \
		local value="$$1"; \
		local size=$${#value}; \
		(( size >= 1 && size <= 100 )) || return 1; \
		local first="$${value:0:1}"; \
		local last="$${value:$$(($${#value} - 1)):1}"; \
		is_ascii_alnum "$$first" || return 1; \
		is_ascii_alnum "$$last" || return 1; \
		local previous_separator=0; \
		local char=""; \
		for ((i = 0; i < size; i++)); do \
			char="$${value:$$i:1}"; \
			if is_ascii_alnum "$$char"; then \
				previous_separator=0; \
				continue; \
			fi; \
			if [[ "$$char" == "-" || "$$char" == "_" || "$$char" == "." ]]; then \
				if (( previous_separator == 1 )); then return 1; fi; \
				previous_separator=1; \
				continue; \
			fi; \
			return 1; \
		done; \
		return 0; \
	}; \
	normalize_github_origin() { \
		local origin_url="$$1"; \
		local owner=""; \
		local repository=""; \
		if [[ "$$origin_url" =~ ^https://github\.com/([^[:space:]/]+)/([^/?#[:space:]]+)(\.git)?$$ ]]; then \
			owner="$${BASH_REMATCH[1]}"; \
			repository="$${BASH_REMATCH[2]}"; \
		elif [[ "$$origin_url" =~ ^git@github\.com:([^[:space:]/]+)/([^/?#[:space:]]+)(\.git)?$$ ]]; then \
			owner="$${BASH_REMATCH[1]}"; \
			repository="$${BASH_REMATCH[2]}"; \
		else \
			return 1; \
		fi; \
		repository="$${repository%.git}"; \
		is_canonical_owner "$$owner" || return 1; \
		is_canonical_repository "$$repository" || return 1; \
		echo "$$owner/$$repository"; \
	}; \
	origin_url="$$(git remote get-url origin 2>/dev/null || true)"; \
	if normalized_repository="$$(normalize_github_origin "$$origin_url")"; then \
		/usr/libexec/PlistBuddy -c "Add :UsageBarUpdateRepository string $$normalized_repository" "$(APP_DIR)/Contents/Info.plist"; \
	fi; \
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
