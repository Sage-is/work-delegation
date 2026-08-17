# 1. help (default target)
help:
	@echo "================================================"
	@echo "       $(OWNER)/$(PROJECT_NAME) by Startr.Cloud"
	@echo "================================================"
	@echo "This is the default make command."
	@echo "This command lists available make commands."
	@echo ""
	@echo "Usage example:"
	@echo "    make install"
	@echo ""
	@echo "Available make commands:"
	@echo ""
	@LC_ALL=C $(MAKE) -pRrq -f $(firstword $(MAKEFILE_LIST)) : 2>/dev/null | \
		awk -v RS= -F: '/(^|\n)# Files(\n|$$)/,/(^|\n)# Finished Make data base/ { \
		if ($$1 !~ "^[#.]") {print $$1}}' | \
		sort | \
		grep -E -v -e '^[^[:alnum:]]' -e '^$@$$'
	@echo ""

# 2. Dynamic variables (git-derived)
PROJECTPATH := $(shell git rev-parse --show-toplevel)
PROJECT     := $(shell echo $$(basename $(PROJECTPATH)) | tr '[:upper:]' '[:lower:]')
FULL_BRANCH := $(shell git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null || echo "develop")
BRANCH      := $(shell echo $(FULL_BRANCH) | sed 's/.*\///' | tr '[:upper:]' '[:lower:]')
TAG         := $(shell git describe --always --tag 2>/dev/null || echo "v0.0.0")

REMOTE_URL   := $(shell git config --get remote.origin.url 2>/dev/null || echo "unknown/unknown")
OWNER        := $(shell echo $(REMOTE_URL) | sed -E 's|.*[:/]([^/]+)/[^/]+(.git)?$$|\1|')
PROJECT_NAME := $(shell echo $(REMOTE_URL) | sed -E 's|.*[:/][^/]+/([^/]+)(.git)?$$|\1|' | sed 's/\.git$$//')

CONTAINER := $(PROJECT)-$(BRANCH)

# 3. Load environment overrides from .env if present
-include .env

# 4. Project-specific targets — cross-harness installers
CLAUDE_SKILL_DIR   := $(HOME)/.claude/skills/delegate-edit
CODEX_PROMPT_DIR   := $(HOME)/.codex/prompts
OPENCODE_CMD_DIR   := $(HOME)/.config/opencode/command
BIN_DIR            := $(HOME)/bin

install: install-claude install-codex install-opencode install-bin
	@echo "OK: installed for Claude Code, Codex, and opencode."

# Hard gate: never install a wrapper that kills processes by name.
# A name-based sweep already killed the user's interactive TUI once
# (docs/stall-investigation.md). PID-tree kills use kill + ps -o pid=,ppid=.
guard-no-name-kills:
	@! grep -nE 'pgrep|pkill|killall' skill/scripts/oc-edit skill/scripts/oc-delegate-hook.sh \
		|| { echo "REFUSED: name-based kill in wrapper (hard gate, docs/stall-investigation.md)"; exit 1; }

install-bin: guard-no-name-kills
	@mkdir -p $(BIN_DIR)
	install -m 0755 skill/scripts/oc-edit $(BIN_DIR)/oc-edit
	install -m 0755 skill/scripts/oc-stall-verdict $(BIN_DIR)/oc-stall-verdict
	@echo "OK: $(BIN_DIR)/oc-edit"

install-claude: guard-no-name-kills
	@mkdir -p $(CLAUDE_SKILL_DIR)/scripts
	install -m 0644 skill/SKILL.md $(CLAUDE_SKILL_DIR)/SKILL.md
	install -m 0755 skill/scripts/oc-edit $(CLAUDE_SKILL_DIR)/scripts/oc-edit
	install -m 0755 skill/scripts/oc-stall-verdict $(CLAUDE_SKILL_DIR)/scripts/oc-stall-verdict
	install -m 0755 skill/scripts/oc-delegate-hook.sh $(CLAUDE_SKILL_DIR)/scripts/oc-delegate-hook.sh
	@echo "OK: $(CLAUDE_SKILL_DIR)"

install-codex:
	@mkdir -p $(CODEX_PROMPT_DIR)
	install -m 0644 harness/codex/delegate-edit.md $(CODEX_PROMPT_DIR)/delegate-edit.md
	@echo "OK: $(CODEX_PROMPT_DIR)/delegate-edit.md"

install-opencode:
	@mkdir -p $(OPENCODE_CMD_DIR)
	install -m 0644 harness/opencode/delegate-edit.md $(OPENCODE_CMD_DIR)/delegate-edit.md
	@echo "OK: $(OPENCODE_CMD_DIR)/delegate-edit.md"

doctor:
	@$(BIN_DIR)/oc-edit --doctor

uninstall:
	rm -rf $(CLAUDE_SKILL_DIR)
	rm -f $(BIN_DIR)/oc-edit
	rm -f $(CODEX_PROMPT_DIR)/delegate-edit.md
	rm -f $(OPENCODE_CMD_DIR)/delegate-edit.md
	@echo "OK: removed from every harness."

# 5. show_vars + verify (debug / one-shot self-check)
show_vars:
	@echo "=== Dynamic Variables ==="
	@echo "PROJECTPATH=$(PROJECTPATH)"
	@echo "PROJECT=$(PROJECT)"
	@echo "OWNER=$(OWNER)"
	@echo "PROJECT_NAME=$(PROJECT_NAME)"
	@echo "FULL_BRANCH=$(FULL_BRANCH)"
	@echo "BRANCH=$(BRANCH)"
	@echo "TAG=$(TAG)"
	@echo "CONTAINER=$(CONTAINER)"
	@echo "REMOTE_URL=$(REMOTE_URL)"
	@echo ""

verify: show_vars require_gitflow_next
	@echo "=== Targets defined in this Makefile ==="
	@LC_ALL=C $(MAKE) -pRrq -f $(firstword $(MAKEFILE_LIST)) : 2>/dev/null | \
		awk -v RS= -F: '/(^|\n)# Files(\n|$$)/,/(^|\n)# Finished Make data base/ { \
		if ($$1 !~ "^[#.]") {print "  " $$1}}' | \
		sort -u | \
		grep -E -v -e '^  [^[:alnum:]]'
	@echo ""
	@echo "OK: Makefile scaffold verified."

# 6. Git-flow-next release/hotfix flow
require_gitflow_next:
	@if ! git flow version 2>/dev/null | grep -q 'git-flow-next'; then \
		echo "Error: git-flow-next required (Go rewrite). Install: brew install git-flow-next"; \
		exit 1; \
	fi

minor_release: require_gitflow_next
	git flow release start $$(git tag --sort=-v:refname | sed 's/^v//' | head -n 1 | awk -F'.' '{print $$1"."$$2+1".0"}') && echo "or use 'make release_finish' to finish the release"

patch_release: require_gitflow_next
	git flow release start $$(git tag --sort=-v:refname | sed 's/^v//' | head -n 1 | awk -F'.' '{print $$1"."$$2"."$$3+1}') && echo "or use 'make release_finish' to finish the release"

major_release: require_gitflow_next
	git flow release start $$(git tag --sort=-v:refname | sed 's/^v//' | head -n 1 | awk -F'.' '{print $$1+1".0.0"}') && echo "or use 'make release_finish' to finish the release"

hotfix: require_gitflow_next
	git flow hotfix start $$(git tag --sort=-v:refname | sed 's/^v//' | head -n 1 | awk -F'.' '{print $$1"."$$2"."$$3"."$$4+1}') && echo "or use 'make hotfix_finish' to finish the hotfix"

release_finish: require_gitflow_next
	git flow release finish && git push origin develop && git push origin master && git push --tags && git checkout develop

hotfix_finish: require_gitflow_next
	git flow hotfix finish && git push origin develop && git push origin master && git push --tags && git checkout master

# 7. things_clean
things_clean:
	git clean --exclude='!.env*' -Xdf

# 8. .PHONY declarations
.PHONY: help show_vars verify require_gitflow_next \
	minor_release patch_release major_release hotfix \
	release_finish hotfix_finish things_clean \
	install install-all install-bin install-claude install-codex install-opencode \
	doctor uninstall guard-no-name-kills
