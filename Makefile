.PHONY: install uninstall lint help

install:
	@bash setup.sh

uninstall:
	@bash uninstall.sh

lint:
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck notify.sh notify-clear.sh setup.sh uninstall.sh; \
	else \
		echo "shellcheck not installed. Install with: brew install shellcheck"; \
		exit 1; \
	fi

help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "  install   - Install scripts and config to ~/.claude/"
	@echo "  uninstall - Remove hooks and scripts"
	@echo "  lint      - Run shellcheck on all scripts"
	@echo "  help      - Show this help message"
