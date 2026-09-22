# PDF Unpack — common tasks.
# Requires: xcodegen (all targets), create-dmg (`make dmg` only), python3 (`make fixtures` only).
#   brew install xcodegen create-dmg

PROJECT := PDF Unpack.xcodeproj
SCHEME  := PDF Unpack
APP     := build/Build/Products/Release/$(SCHEME).app
DMG     := $(SCHEME).dmg
VENV    := tools/.venv

.DEFAULT_GOAL := help
.PHONY: help generate test build dmg fixtures clean

help: ## List available targets
	@grep -E '^[a-z][a-zA-Z-]*:.*##' $(MAKEFILE_LIST) | sed -E 's/:.*## / — /' | sort

generate: ## Regenerate the Xcode project from project.yml
	xcodegen generate

test: generate ## Run the unit tests
	xcodebuild test -project "$(PROJECT)" -scheme "$(SCHEME)" \
		-destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO

build: generate ## Build a Release .app (compile check; unsigned)
	xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -configuration Release \
		-derivedDataPath build CODE_SIGNING_ALLOWED=NO clean build

dmg: build ## Build, ad-hoc sign, and package a distributable .dmg
	@command -v create-dmg >/dev/null || { echo "Install create-dmg: brew install create-dmg"; exit 1; }
	codesign --force --deep --sign - "$(APP)"
	rm -f "$(DMG)"
	create-dmg --volname "$(SCHEME)" --window-size 500 320 --icon-size 100 \
		--icon "$(SCHEME).app" 130 150 --app-drop-link 370 150 "$(DMG)" "$(APP)"

fixtures: ## Regenerate the test PDFs in fixtures/ (pikepdf goes into tools/.venv)
	python3 -m venv $(VENV)
	$(VENV)/bin/pip install --quiet --requirement tools/requirements.txt
	$(VENV)/bin/python tools/make_fixtures.py

clean: ## Remove build artifacts
	rm -rf build "$(DMG)"
