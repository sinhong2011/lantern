# Lantern — local macOS loop
#   make run       build Debug and relaunch the menu bar app
#   make relaunch  reopen the last Debug build (no compile)
#   make open      generate + open Xcode
#   make dist      zip a Release build (Sparkle signing happens in CI)

.DEFAULT_GOAL := help

SCHEME  := Lantern
CONFIG  ?= Debug
DERIVED := $(CURDIR)/build/DerivedData
APP     := $(DERIVED)/Build/Products/$(CONFIG)/$(SCHEME).app
PROJECT := Lantern.xcodeproj
API     := http://127.0.0.1:19247
DIST    := $(CURDIR)/dist

XCODEBUILD_FLAGS := \
	-project $(PROJECT) \
	-scheme $(SCHEME) \
	-configuration $(CONFIG) \
	-derivedDataPath $(DERIVED) \
	CODE_SIGN_IDENTITY=- \
	CODE_SIGNING_REQUIRED=NO \
	CODE_SIGNING_ALLOWED=YES

.PHONY: help generate build run relaunch kill open status dist clean distclean

help:
	@echo "Lantern"
	@echo "  make run        generate, build $(CONFIG), relaunch"
	@echo "  make build      generate + xcodebuild"
	@echo "  make relaunch   quit running app and open $(CONFIG) build"
	@echo "  make kill       quit Lantern"
	@echo "  make open       generate and open Xcode"
	@echo "  make status     Control API /status"
	@echo "  make dist       Release zip at dist/updates/Lantern.zip"
	@echo "  make clean      delete DerivedData"
	@echo "  make distclean  DerivedData + generated $(PROJECT)"
	@echo "  CONFIG=Release make run"

generate:
	@command -v xcodegen >/dev/null 2>&1 || { \
		echo "XcodeGen is required. Install with: brew install xcodegen" >&2; \
		exit 1; \
	}
	xcodegen generate

build: generate
	xcodebuild $(XCODEBUILD_FLAGS) build
	@echo "Built: $(APP)"

run: build relaunch

relaunch:
	@test -d "$(APP)" || { echo "No app at $(APP). Run make build first." >&2; exit 1; }
	@-$(MAKE) kill
	@sleep 0.4
	open "$(APP)"
	@echo "Launched $(APP)"

kill:
	-pkill -x Lantern

open: generate
	open "$(PROJECT)"

status:
	@curl -sS "$(API)/status" | python3 -m json.tool

dist:
	$(MAKE) build CONFIG=Release
	rm -rf "$(DIST)/updates"
	mkdir -p "$(DIST)/updates"
	ditto -c -k --keepParent \
		"$(DERIVED)/Build/Products/Release/$(SCHEME).app" \
		"$(DIST)/updates/Lantern.zip"
	@echo "Zipped: $(DIST)/updates/Lantern.zip"

clean:
	rm -rf "$(DERIVED)"

distclean: clean
	rm -rf "$(PROJECT)" "$(DIST)"
