SHELL := /bin/bash

CONFIGS ?= vim tmux zsh
OUT_DIR ?= packages/config

.PHONY: help pack-vim pack-tmux pack-zsh pack-configs

help:
	@printf '%s\n' 'OMW config packaging'
	@printf '%s\n' ''
	@printf '%s\n' 'Targets:'
	@printf '%s\n' '  make pack-vim OUT_DIR=packages/config'
	@printf '%s\n' '  make pack-tmux OUT_DIR=packages/config'
	@printf '%s\n' '  make pack-zsh OUT_DIR=packages/config'
	@printf '%s\n' '  make pack-configs OUT_DIR=packages/config'
	@printf '%s\n' ''
	@printf '%s\n' 'Variables:'
	@printf '%s\n' '  OUT_DIR=/path/to/output'
	@printf '%s\n' '  CONFIGS="vim tmux zsh"'

pack-vim:
	@set -eu; \
	cfg="vim"; \
	required="config/vim/vim9"; \
	if [[ ! -d "$$required" ]] || [[ -z "$$(find "$$required" -mindepth 1 -print -quit)" ]]; then \
		printf 'Config source is missing or empty: %s\n' "$$required" >&2; \
		exit 1; \
	fi; \
	mkdir -p "$(OUT_DIR)"; \
	COPYFILE_DISABLE=1 tar --format=ustar --exclude='.git' -czf "$(OUT_DIR)/$$cfg.tar.gz" -C config "$$cfg"; \
	printf 'Packed config/%s -> %s\n' "$$cfg" "$(OUT_DIR)/$$cfg.tar.gz"

pack-tmux:
	@set -eu; \
	cfg="tmux"; \
	required="config/tmux/.tmux"; \
	if [[ ! -d "$$required" ]] || [[ -z "$$(find "$$required" -mindepth 1 -print -quit)" ]]; then \
		printf 'Config source is missing or empty: %s\n' "$$required" >&2; \
		exit 1; \
	fi; \
	mkdir -p "$(OUT_DIR)"; \
	COPYFILE_DISABLE=1 tar --format=ustar --exclude='.git' -czf "$(OUT_DIR)/$$cfg.tar.gz" -C config "$$cfg"; \
	printf 'Packed config/%s -> %s\n' "$$cfg" "$(OUT_DIR)/$$cfg.tar.gz"

pack-zsh:
	@set -eu; \
	cfg="zsh"; \
	required="config/zsh/.oh-my-zsh"; \
	if [[ ! -d "$$required" ]] || [[ -z "$$(find "$$required" -mindepth 1 -print -quit)" ]]; then \
		printf 'Config source is missing or empty: %s\n' "$$required" >&2; \
		exit 1; \
	fi; \
	mkdir -p "$(OUT_DIR)"; \
	COPYFILE_DISABLE=1 tar --format=ustar --exclude='.git' -czf "$(OUT_DIR)/$$cfg.tar.gz" -C config "$$cfg"; \
	printf 'Packed config/%s -> %s\n' "$$cfg" "$(OUT_DIR)/$$cfg.tar.gz"

pack-configs:
	@set -eu; \
	for cfg in $(CONFIGS); do \
		case "$$cfg" in \
			vim) $(MAKE) pack-vim OUT_DIR="$(OUT_DIR)" ;; \
			tmux) $(MAKE) pack-tmux OUT_DIR="$(OUT_DIR)" ;; \
			zsh) $(MAKE) pack-zsh OUT_DIR="$(OUT_DIR)" ;; \
			*) printf 'Unsupported config: %s\n' "$$cfg" >&2; exit 2 ;; \
		esac; \
	done
