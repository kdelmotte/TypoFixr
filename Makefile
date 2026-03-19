# Use Xcode toolchain (not Command Line Tools) for XCTest support
DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR

CERT_NAME   := TypoFixrDev
APP_BUNDLE  := $(HOME)/Applications/TypoFixr.app
APP_BINARY  := $(APP_BUNDLE)/Contents/MacOS/TypoFixr
APP_DOMAIN  := com.typofixr.app
XCODE_DERIVED_DATA := .build/xcode
XCODE_RELEASE_APP := $(XCODE_DERIVED_DATA)/Build/Products/Release/TypoFixr.app

.PHONY: build release test deploy preflight-dmg xcode-build xcode-test

build:
	swift build -c debug

release:
	swift build -c release

test:
	swift test --enable-xctest

deploy:
	@echo "==> Resetting onboarding..."
	defaults write $(APP_DOMAIN) hasCompletedOnboarding -bool false
	defaults delete $(APP_DOMAIN) keyboardShortcut 2>/dev/null || true
	@echo "==> Stopping running instance..."
	pkill -f TypoFixr || true
	sleep 0.5
	@echo "==> Building app bundle..."
	$(DEVELOPER_DIR)/usr/bin/xcodebuild -project TypoFixr.xcodeproj -scheme TypoFixr -configuration Release -derivedDataPath "$(XCODE_DERIVED_DATA)" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
	@echo "==> Installing app bundle..."
	mkdir -p $$(dirname "$(APP_BUNDLE)")
	ditto "$(XCODE_RELEASE_APP)" "$(APP_BUNDLE)"
	@echo "==> Signing with $(CERT_NAME)..."
	codesign --force --deep --sign "$(CERT_NAME)" "$(APP_BUNDLE)"
	@echo "==> Launching..."
	open "$(APP_BUNDLE)"
	@echo "Done. Accessibility permissions should persist across deploys."

preflight-dmg:
	./scripts/preflight_release_dmg.sh

xcode-build:
	xcodebuild -project TypoFixr.xcodeproj -scheme TypoFixr -configuration Debug build

xcode-test:
	xcodebuild -project TypoFixr.xcodeproj -scheme TypoFixr -configuration Debug test
