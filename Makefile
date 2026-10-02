# Use Xcode toolchain (not Command Line Tools) for XCTest support
DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR

CERT_NAME   := TypoFixrDev
CODE_SIGN_FLAGS :=
LAUNCH_AFTER_DEPLOY := 1
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
	@echo "==> Building app bundle..."
	$(DEVELOPER_DIR)/usr/bin/xcodebuild -project TypoFixr.xcodeproj -scheme TypoFixr -configuration Release -derivedDataPath "$(XCODE_DERIVED_DATA)" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
	@echo "==> Signing with $(CERT_NAME)..."
	codesign --force --deep $(CODE_SIGN_FLAGS) --sign "$(CERT_NAME)" "$(XCODE_RELEASE_APP)"
	codesign --verify --deep --strict "$(XCODE_RELEASE_APP)"
	@if [ "$(LAUNCH_AFTER_DEPLOY)" = "1" ]; then \
		pkill -f "$(APP_BINARY)" || true; \
		sleep 0.5; \
	fi
	@echo "==> Installing app bundle..."
	mkdir -p $$(dirname "$(APP_BUNDLE)")
	ditto "$(XCODE_RELEASE_APP)" "$(APP_BUNDLE)"
	@if [ "$(LAUNCH_AFTER_DEPLOY)" = "1" ]; then open "$(APP_BUNDLE)"; fi
	@echo "Done. Preferences preserved. Accessibility access depends on the signing identity."

preflight-dmg:
	./scripts/preflight_release_dmg.sh

xcode-build:
	xcodebuild -project TypoFixr.xcodeproj -scheme TypoFixr -configuration Debug build

xcode-test:
	xcodebuild -project TypoFixr.xcodeproj -scheme TypoFixr -configuration Debug test
