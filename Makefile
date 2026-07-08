# PDF Unpack — common tasks.
# Requires: xcodegen (all targets) and create-dmg (`make dmg` only).
#   brew install xcodegen create-dmg

PROJECT := PDF Unpack.xcodeproj
SCHEME  := PDF Unpack
APP     := build/Build/Products/Release/$(SCHEME).app
DMG     := $(SCHEME).dmg

.DEFAULT_GOAL := help
.PHONY: help generate test build dmg clean

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

clean: ## Remove build artifacts
	rm -rf build "$(DMG)"
