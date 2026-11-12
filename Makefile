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
PI_PROMPT_DIR      := $(HOME)/.pi/agent/prompts
PI_SKILL_DIR       := $(HOME)/.pi/agent/skills/delegate-edit
BIN_DIR            := $(HOME)/bin

install: migrate-names install-claude install-codex install-opencode install-pi install-bin
	@echo "OK: installed for Claude Code, Codex, opencode, and Pi."

# One-time cleanup from the oc-* names (2026-09-04). Old binaries and installed
# scripts go; the ledger keeps its history under the new path. Idempotent.
migrate-names:
	@rm -f $(BIN_DIR)/oc-edit $(BIN_DIR)/oc-stall-verdict
	@rm -f $(CLAUDE_SKILL_DIR)/scripts/oc-edit $(CLAUDE_SKILL_DIR)/scripts/oc-stall-verdict \
		$(CLAUDE_SKILL_DIR)/scripts/oc-delegate-hook.sh
	@if [ -f $(HOME)/.local/state/oc-edit/log.jsonl ]; then \
		mkdir -p $(HOME)/.local/state/delegate; \
		mv -n $(HOME)/.local/state/oc-edit/log.jsonl $(HOME)/.local/state/delegate/log.jsonl; \
		rmdir $(HOME)/.local/state/oc-edit 2>/dev/null || true; \
		echo "OK: ledger moved to ~/.local/state/delegate/log.jsonl"; fi

# Hard gate: never install a wrapper that kills processes by name.
# A name-based sweep already killed the user's interactive TUI once
# (docs/stall-investigation.md). PID-tree kills use kill + ps -o pid=,ppid=.
guard-no-name-kills:
	@! grep -nE 'pgrep|pkill|killall' skill/scripts/delegate-edit skill/scripts/delegate-agent skill/scripts/delegate-hook.sh \
		|| { echo "REFUSED: name-based kill in wrapper (hard gate, docs/stall-investigation.md)"; exit 1; }

install-bin: guard-no-name-kills
	@mkdir -p $(BIN_DIR)
	install -m 0755 skill/scripts/delegate-edit $(BIN_DIR)/delegate-edit
	install -m 0755 skill/scripts/delegate-agent $(BIN_DIR)/delegate-agent
	install -m 0755 skill/scripts/delegate-stall-verdict $(BIN_DIR)/delegate-stall-verdict
	install -m 0755 skill/scripts/delegate-cost $(BIN_DIR)/delegate-cost
	@echo "OK: $(BIN_DIR)/delegate-edit"

install-claude: guard-no-name-kills
	@mkdir -p $(CLAUDE_SKILL_DIR)/scripts $(CLAUDE_SKILL_DIR)/references
	install -m 0644 skill/SKILL.md $(CLAUDE_SKILL_DIR)/SKILL.md
	install -m 0644 skill/references/*.md $(CLAUDE_SKILL_DIR)/references/
	install -m 0755 skill/scripts/delegate-edit $(CLAUDE_SKILL_DIR)/scripts/delegate-edit
	install -m 0755 skill/scripts/delegate-agent $(CLAUDE_SKILL_DIR)/scripts/delegate-agent
	install -m 0755 skill/scripts/delegate-stall-verdict $(CLAUDE_SKILL_DIR)/scripts/delegate-stall-verdict
	install -m 0755 skill/scripts/delegate-cost $(CLAUDE_SKILL_DIR)/scripts/delegate-cost
	install -m 0755 skill/scripts/delegate-hook.sh $(CLAUDE_SKILL_DIR)/scripts/delegate-hook.sh
	@echo "OK: $(CLAUDE_SKILL_DIR)"

install-codex:
	@mkdir -p $(CODEX_PROMPT_DIR)
	install -m 0644 harness/codex/delegate-edit.md $(CODEX_PROMPT_DIR)/delegate-edit.md
	@echo "OK: $(CODEX_PROMPT_DIR)/delegate-edit.md"

install-opencode:
	@mkdir -p $(OPENCODE_CMD_DIR)
	install -m 0644 harness/opencode/delegate-edit.md $(OPENCODE_CMD_DIR)/delegate-edit.md
	@echo "OK: $(OPENCODE_CMD_DIR)/delegate-edit.md"

# Pi reads prompt templates from ~/.pi/agent/prompts and Agent Skills from
# ~/.pi/agent/skills, so it gets the /delegate-edit command and the same skill
# directory Claude Code gets. Installed whether or not pi is present yet.
install-pi: guard-no-name-kills
	@mkdir -p $(PI_PROMPT_DIR) $(PI_SKILL_DIR)/scripts $(PI_SKILL_DIR)/references
	install -m 0644 harness/pi/delegate-edit.md $(PI_PROMPT_DIR)/delegate-edit.md
	install -m 0644 skill/SKILL.md $(PI_SKILL_DIR)/SKILL.md
	install -m 0644 skill/references/*.md $(PI_SKILL_DIR)/references/
	install -m 0755 skill/scripts/delegate-edit $(PI_SKILL_DIR)/scripts/delegate-edit
	install -m 0755 skill/scripts/delegate-agent $(PI_SKILL_DIR)/scripts/delegate-agent
	@echo "OK: $(PI_PROMPT_DIR)/delegate-edit.md and $(PI_SKILL_DIR)"

doctor:
	@$(BIN_DIR)/delegate-edit --doctor

# Not a prerequisite of install: guard-no-name-kills stays the only gate there.
test:
	@bash tests/lock.sh
	@bash tests/agent.sh
	@bash tests/wrapper.sh
	@bash tests/hook.sh
	@bash tests/cost.sh
	@python3 -c 'import flask' 2>/dev/null && python3 -m unittest app/test_admin.py || echo "note  Flask missing: app tests skipped (pip install flask)"
	@$(MAKE) -s kit_check

# The admin: review, search, star, tag, note, and diff every delegation.
# Reads the live ledger on each request; marks and patches live beside it.
admin:
	@python3 -c 'import flask' 2>/dev/null || { echo "Flask missing: pip install flask"; exit 1; }
	@python3 app/admin.py

ledger: admin

# The vendored kit (startr.style and startr.swap) must match its pins. A drift
# is a change nobody reviewed, so it fails rather than warns. Same-origin only:
# neither file ever loads from a CDN.
kit_check:
	@fail=0; cd app/static/vendor && for f in startr-swap/startr-swap.js startr.style/style.css; do \
	  if [ ! -f "$$f.sha256" ]; then echo "MISSING PIN: $$f.sha256"; fail=1; continue; fi; \
	  want=$$(cat "$$f.sha256"); got=$$(shasum -a 256 "$$f" | awk '{print $$1}'); \
	  if [ "$$want" != "$$got" ]; then echo "DRIFT: $$f"; fail=1; \
	  else echo "ok  pin  $$f ($$(wc -c < "$$f" | tr -d ' ') bytes)"; fi; done; \
	if grep -q "@import" startr.style/style.css; then echo "REFUSED: style.css carries @import"; fail=1; fi; \
	if grep -Eq "url\\(['\"]?(https?:|//)" startr.style/style.css; then echo "REFUSED: style.css has off-origin url()"; fail=1; fi; \
	exit $$fail

# Start the stats over: the ledger moves to log-<date>.archive.jsonl beside
# itself and a fresh file begins. History stays readable; nothing is deleted.
ledger_archive:
	@L=$(HOME)/.local/state/delegate/log.jsonl; [ -s "$$L" ] || { echo "nothing to archive"; exit 0; }; \
	A=$${L%.jsonl}-$$(date +%Y-%m-%d).archive.jsonl; i=1; \
	while [ -e "$$A" ]; do A=$${L%.jsonl}-$$(date +%Y-%m-%d)-$$i.archive.jsonl; i=$$((i+1)); done; \
	mv "$$L" "$$A"; : > "$$L"; echo "archived $$(wc -l < "$$A" | tr -d ' ') rows to $$A"

# Patch files older than 90 days go; the ledger rows keep their stat line.
diffs_prune:
	@n=$$(find $(HOME)/.local/state/delegate/diffs -name '*.patch' -mtime +90 -print -delete 2>/dev/null | wc -l | tr -d ' '); \
	echo "pruned $$n patch file(s) older than 90 days"

# The measurement: make matrix LANES=go/deepseek-v4-flash,ollama/qwen3.5:9b
# Six tasks per lane (TASKS=a,b for some) through the real wrapper; rows land in results/matrix-<date>.md.
matrix:
	@TASKS=$(TASKS) bash tests/matrix/run.sh "$(LANES)"

# What the matrix has not scored yet: catalogue models new since the last run.
unmeasured:
	@python3 tests/matrix/unmeasured.py $(or $(PREFIX),go)

# Where Claude Code's tokens go, and what delegation saves: make cost SINCE=2026-09-05
cost:
	@python3 skill/scripts/delegate-cost $(if $(SINCE),--since $(SINCE),)

uninstall:
	rm -rf $(CLAUDE_SKILL_DIR)
	rm -f $(BIN_DIR)/delegate-edit $(BIN_DIR)/delegate-agent $(BIN_DIR)/delegate-stall-verdict $(BIN_DIR)/delegate-cost
	rm -f $(CODEX_PROMPT_DIR)/delegate-edit.md
	rm -f $(OPENCODE_CMD_DIR)/delegate-edit.md
	rm -rf $(PI_SKILL_DIR)
	rm -f $(PI_PROMPT_DIR)/delegate-edit.md
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
.PHONY: help show_vars verify require_gitflow_next cost unmeasured \
	minor_release patch_release major_release hotfix \
	release_finish hotfix_finish things_clean \
	install install-bin install-claude install-codex install-opencode install-pi \
	migrate-names doctor test matrix ledger admin kit_check ledger_archive diffs_prune uninstall guard-no-name-kills

## >>> startr worktree block v1 (startr.sh/Makefile, 2026-11-12) >>>
## One checkout per repo. A worktree is for one parallel task, and it goes
## the day its branch lands; a landed branch goes too. wt_check fails while
## either lingers, so the rule is a gate, not a memory.
## To update a repo, replace everything between the two marker lines.
## Guide: https://startr.sh/docs/makefile-worktrees/
##   make wt NAME=quick-note       feature/quick-note from WT_BASE, in ../<repo>-wt/quick-note
##   make wt NAME=fix/typo         a name with a slash is the branch; the folder is fix-typo
##   make wt_list                  each worktree and spare branch: ahead/behind, changes, age
##   make wt_done NAME=quick-note  clean and landed only: removes the worktree and its branch
##   make wt_tidy                  wt_done for every clean, landed worktree and branch
##   make wt_check                 fails on a landed worktree or branch, or one over WT_DAYS
## "Landed" means merging the branch into WT_BASE changes nothing: merged,
## squashed or rebased in. The remote branch is never touched.
WT_BASE ?= $(shell for b in develop main master; do git rev-parse -q --verify "refs/heads/$$b" >/dev/null && { echo $$b; break; }; done)
WT_MAX ?= 3
WT_DAYS ?= 3
WT_KEEP ?= develop main master gh-pages

.PHONY: wt wt_list wt_done wt_tidy wt_check

## Shell functions the five targets share. Every worktree but the main
## checkout prints as "path<TAB>branch" ("-" when detached).
define wt_sh
tab=$$(printf '\t'); now=$$(date +%s); base="$(WT_BASE)"; \
main=$$(cd "$$(git rev-parse --path-format=absolute --git-common-dir)/.." && pwd); \
root="$$main-wt"; \
git worktree prune; \
worktrees() { git worktree list --porcelain | awk '/^worktree /{n++; p=substr($$0,10)} n>1 && /^branch /{print p "\t" substr($$0,19)} n>1 && /^detached/{print p "\t-"}'; }; \
spare_branches() { held=$$(git worktree list --porcelain | sed -n 's|^branch refs/heads/||p'); \
	git for-each-ref --format='%(refname:short)' refs/heads | while read -r b; do \
	case " $(WT_KEEP) $$base " in *" $$b "*) continue;; esac; \
	printf '%s\n' "$$held" | grep -qxF "$$b" || echo "$$b"; done; }; \
contained() { git merge-base --is-ancestor "$$1" "$$base" && return 0; \
	t=$$(git merge-tree --write-tree "$$base" "$$1" 2>/dev/null) && [ "$$t" = "$$(git rev-parse "$$base^{tree}")" ]; }; \
worked() { [ "$$(git reflog show "refs/heads/$$1" 2>/dev/null | wc -l | tr -d ' ')" -gt 1 ]; }; \
age() { c=$$(git reflog show --date=unix --format=%gd "refs/heads/$$1" 2>/dev/null | tail -1 | sed -n 's/.*@{\([0-9]*\)}$$/\1/p'); \
	[ -n "$$c" ] && echo $$(( (now - c) / 86400 )) || echo 0; }; \
changes() { git -C "$$1" status --porcelain | wc -l | tr -d ' '; }; \
remove_one() { if [ -n "$$1" ]; then git worktree remove "$$1" || return 1; echo "Removed $$1"; fi; \
	if [ "$$2" != "-" ]; then git branch -D "$$2" >/dev/null && echo "Deleted $$2 (its work is in $$base)"; \
	git rev-parse -q --verify "refs/remotes/origin/$$2" >/dev/null && echo "  origin still has it: git push origin --delete $$2"; fi; \
	rmdir "$$root" 2>/dev/null; true; }
endef

## The bodies of wt_list and wt_check, shared with wt and wt_tidy. They are
## defines, not recursive $(MAKE) calls, so `make -n wt` runs nothing.
define wt_list_sh
echo "base: $${base:-none}"; \
worktrees | while IFS="$$tab" read -r p b; do \
	n=$$(changes "$$p"); line="$$p  $$b  $$n changed"; \
	if [ "$$b" != "-" ] && [ -n "$$base" ]; then \
		line="$$line  +$$(git rev-list --count "$$base..$$b")/-$$(git rev-list --count "$$b..$$base")  $$(age "$$b")d"; \
		[ "$$n" = 0 ] && worked "$$b" && contained "$$b" && line="$$line  LANDED: make wt_done"; \
	fi; echo "$$line"; done; \
[ -n "$$base" ] && spare_branches | while read -r b; do \
	line="branch $$b  +$$(git rev-list --count "$$base..$$b")/-$$(git rev-list --count "$$b..$$base")  $$(age "$$b")d"; \
	contained "$$b" && line="$$line  LANDED: make wt_done NAME=$$b"; echo "$$line"; done; true
endef

define wt_check_sh
[ -n "$$base" ] || { echo "wt_check: no develop, main or master branch here; skipped"; exit 0; }; \
bad=$$( worktrees | while IFS="$$tab" read -r p b; do \
	[ "$$b" = "-" ] && continue; \
	[ "$$(changes "$$p")" = 0 ] && worked "$$b" && contained "$$b" && { echo "  landed worktree: $$p ($$b)"; continue; }; \
	[ "$$(age "$$b")" -le $(WT_DAYS) ] || echo "  $$(age "$$b") days old: $$p ($$b); land it or make wt_done"; done; \
	spare_branches | while read -r b; do contained "$$b" && echo "  landed branch: $$b"; done ); \
[ -z "$$bad" ] || { echo "wt_check failed (WT_DAYS=$(WT_DAYS)):"; echo "$$bad"; echo "make wt_tidy clears what landed; land or drop the rest."; exit 1; }
endef

wt:
	@[ "$(origin NAME)" = "command line" ] || { echo "Usage: make wt NAME=quick-note"; exit 1; }; \
	$(wt_sh); [ -n "$$base" ] || { echo "No develop, main or master branch: set WT_BASE"; exit 1; }; \
	case "$(NAME)" in */*) b="$(NAME)";; *) b="feature/$(NAME)";; esac; \
	dir="$$root/$$(echo "$(NAME)" | tr / -)"; \
	open=$$(worktrees | wc -l | tr -d ' '); \
	[ "$$open" -lt $(WT_MAX) ] || { echo "$$open worktrees open, and WT_MAX is $(WT_MAX). Land one, then make wt_done."; worktrees; exit 1; }; \
	( $(wt_check_sh) ) || { echo "Clear those before a new worktree."; exit 1; }; \
	! git rev-parse -q --verify "refs/heads/$$b" >/dev/null || { echo "$$b already exists"; exit 1; }; \
	git worktree add -q -b "$$b" "$$dir" "$$base" && \
	echo "Ready: cd $$dir ($$b from $$base). When it lands: make wt_done NAME=$(NAME)"

wt_list:
	@$(wt_sh); $(wt_list_sh)

wt_done:
	@[ "$(origin NAME)" = "command line" ] || { echo "Usage: make wt_done NAME=quick-note"; exit 1; }; \
	$(wt_sh); [ -n "$$base" ] || { echo "No develop, main or master branch: set WT_BASE"; exit 1; }; \
	case "$(NAME)" in */*) want="$(NAME)";; *) want="feature/$(NAME)";; esac; \
	dir="$$root/$$(echo "$(NAME)" | tr / -)"; \
	hit=$$(worktrees | awk -F"$$tab" -v d="$$dir" -v b="$$want" '$$1==d || $$2==b {print; exit}'); \
	if [ -n "$$hit" ]; then p=$${hit%%"$$tab"*}; b=$${hit#*"$$tab"}; \
	elif git rev-parse -q --verify "refs/heads/$$want" >/dev/null; then p=; b="$$want"; \
	else echo "No worktree at $$dir and no branch $$want"; exit 1; fi; \
	if [ -n "$$p" ]; then \
		case "$$(pwd -P)/" in "$$(cd "$$p" && pwd -P)/"*) echo "Run it from $$main, not from inside the worktree"; exit 1;; esac; \
		n=$$(changes "$$p"); [ "$$n" = 0 ] || { echo "$$p has $$n uncommitted changes:"; git -C "$$p" status --short; exit 1; }; \
	fi; \
	[ "$$b" = "-" ] || contained "$$b" || { echo "$$b is not in $$base yet: $$(git rev-list --count "$$base..$$b") commits to land"; exit 1; }; \
	remove_one "$$p" "$$b"

wt_tidy:
	@$(wt_sh); [ -n "$$base" ] || { echo "No develop, main or master branch: set WT_BASE"; exit 1; }; \
	worktrees | while IFS="$$tab" read -r p b; do \
		[ "$$b" != "-" ] && [ "$$(changes "$$p")" = 0 ] && worked "$$b" && contained "$$b" && remove_one "$$p" "$$b"; done; \
	spare_branches | while read -r b; do contained "$$b" && remove_one "" "$$b"; done; \
	$(wt_list_sh)

wt_check:
	@$(wt_sh); $(wt_check_sh)
## <<< startr worktree block v1 <<<
