# PDF Unpack — common tasks.
# Requires: xcodegen (all targets), python3 (`make fixtures` only).
#   brew install xcodegen

PROJECT := PDF Unpack.xcodeproj
SCHEME  := PDF Unpack
VENV    := tools/.venv
LOCAL_XCCONFIG := Config/Local.xcconfig
TEAM_SETTING   := ^DEVELOPMENT_TEAM = [A-Z0-9]{10}$$

.DEFAULT_GOAL := help
.PHONY: help generate local-config test build fixtures clean

help: ## List available targets
	@grep -E '^[a-z][a-zA-Z-]*:.*##' $(MAKEFILE_LIST) | sed -E 's/:.*## / — /' | sort

generate: local-config ## Regenerate the Xcode project from project.yml
	xcodegen generate

# Xcode cannot read .env, so the machine-local settings it needs are projected into an xcconfig
# that Config/Base.xcconfig includes. This keeps .env the single place to set DEVELOPMENT_TEAM,
# for both `xcodebuild` and a plain Cmd-R in Xcode. Only a 10-character Team ID is projected;
# quotes and a trailing comment are dropped, and anything else counts as unset.
local-config: ## Project machine-local settings from .env into Config/Local.xcconfig
	@mkdir -p Config
	@printf '// Generated from .env by `make generate`. Do not edit, do not commit.\n' > $(LOCAL_XCCONFIG)
	@if [ -f .env ]; then \
		sed -nE "s/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*[\"']?([A-Z0-9]{10})[\"']?([[:space:]]*(#.*)?)?$$/DEVELOPMENT_TEAM = \1/p" .env \
			>> $(LOCAL_XCCONFIG); \
	fi
	@grep -qE '$(TEAM_SETTING)' $(LOCAL_XCCONFIG) \
		&& echo "✓ DEVELOPMENT_TEAM from .env" \
		|| echo "• no valid DEVELOPMENT_TEAM in .env (a 10-character Team ID) — signing will need a team picked in Xcode"

test: generate ## Run the unit tests
	xcodebuild test -project "$(PROJECT)" -scheme "$(SCHEME)" \
		-destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO

build: generate ## Build a Release .app (compile check; unsigned)
	xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -configuration Release \
		-derivedDataPath build CODE_SIGNING_ALLOWED=NO clean build

fixtures: ## Regenerate the test PDFs in fixtures/ (pikepdf goes into tools/.venv)
	python3 -m venv $(VENV)
	$(VENV)/bin/pip install --quiet --requirement tools/requirements.txt
	$(VENV)/bin/python tools/make_fixtures.py

clean: ## Remove build artifacts
	rm -rf build
