# Use Xcode toolchain (not Command Line Tools) for XCTest support
DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR

CERT_NAME   := TypoFixrDev
APP_BUNDLE  := $(HOME)/Applications/TypoFixr.app
APP_BINARY  := $(APP_BUNDLE)/Contents/MacOS/TypoFixr
APP_DOMAIN  := com.typofixr.app

.PHONY: build release test deploy xcode-build xcode-test

build:
	swift build -c debug

release:
	swift build -c release

test:
	swift test --enable-xctest

deploy: release
	@echo "==> Resetting onboarding..."
	defaults write $(APP_DOMAIN) hasCompletedOnboarding -bool false
	defaults delete $(APP_DOMAIN) keyboardShortcut 2>/dev/null || true
	@echo "==> Stopping running instance..."
	pkill -f TypoFixr || true
	sleep 0.5
	@echo "==> Installing binary..."
	mkdir -p $$(dirname "$(APP_BINARY)")
	cp .build/release/TypoFixr "$(APP_BINARY)"
	@echo "==> Signing with $(CERT_NAME)..."
	codesign --force --deep --sign "$(CERT_NAME)" "$(APP_BUNDLE)"
	@echo "==> Launching..."
	open "$(APP_BUNDLE)"
	@echo "Done. Accessibility permissions should persist across deploys."

xcode-build:
	xcodebuild -project TypoFixr.xcodeproj -scheme TypoFixr -configuration Debug build

xcode-test:
	xcodebuild -project TypoFixr.xcodeproj -scheme TypoFixr -configuration Debug test
