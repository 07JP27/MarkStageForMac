PROJECT_DIR := src
PROJECT := $(PROJECT_DIR)/MarkdStage.xcodeproj
SCHEME := MarkdStage
DERIVED_DATA := build/DerivedData
DEBUG_APP := $(DERIVED_DATA)/Build/Products/Debug/MarkdStage.app
RELEASE_APP := $(DERIVED_DATA)/Build/Products/Release/MarkdStage.app
VERSION ?= 0.1.0
DMG_PATH := build/MarkdStage-v$(VERSION).dmg
NOTARY_ZIP := build/MarkdStage-v$(VERSION).zip
NOTARY_PROFILE ?= MarkdStage
DESTINATION := platform=macOS
MARKDSTAGE_TARGET ?= samples/demo.md
CLI_CHECK_TARGET ?= samples/demo.md

-include .env
export DEVELOPER_ID_APPLICATION

.PHONY: generate build test run run-cli launch-check cli-launch-check pdf-export-check release notarize dmg clean

generate:
	cd $(PROJECT_DIR) && xcodegen generate

build: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -destination '$(DESTINATION)' -derivedDataPath $(DERIVED_DATA) build

test: generate
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' -derivedDataPath $(DERIVED_DATA)

run: build
	open "$(DEBUG_APP)"
	osascript -e 'tell application id "dev.jp27.MarkdStage" to activate'

run-cli: build
	sh scripts/run-local-cli.sh "$(DEBUG_APP)" "$(MARKDSTAGE_TARGET)"

launch-check: build
	sh scripts/launch-smoke-test.sh "$(DEBUG_APP)"

cli-launch-check: build
	sh scripts/cli-launch-smoke-test.sh "$(DEBUG_APP)" "$(CLI_CHECK_TARGET)"

pdf-export-check: build
	sh scripts/pdf-export-smoke-test.sh "$(DEBUG_APP)"

release: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -destination '$(DESTINATION)' -derivedDataPath $(DERIVED_DATA) MARKETING_VERSION="$(VERSION)" build

notarize: release
	@test -n "$(NOTARY_PROFILE)" || (echo "NOTARY_PROFILE is required" && exit 1)
	@test -n "$(DEVELOPER_ID_APPLICATION)" || (echo "DEVELOPER_ID_APPLICATION is required" && exit 1)
	mkdir -p build
	codesign --force --deep --options runtime --timestamp \
		--entitlements src/MarkdStage/Resources/MarkdStage.Release.entitlements \
		--sign "$(DEVELOPER_ID_APPLICATION)" "$(RELEASE_APP)"
	codesign --verify --deep --strict "$(RELEASE_APP)"
	ditto -c -k --keepParent "$(RELEASE_APP)" "$(NOTARY_ZIP)"
	xcrun notarytool submit "$(NOTARY_ZIP)" --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple "$(RELEASE_APP)"

dmg: release
	rm -rf build/dmg-staging
	mkdir -p build/dmg-staging
	cp -R "$(RELEASE_APP)" build/dmg-staging/
	ln -s /Applications build/dmg-staging/Applications
	rm -f "$(DMG_PATH)"
	hdiutil create -volname "MarkdStage" -srcfolder build/dmg-staging -ov -format UDZO "$(DMG_PATH)"

clean:
	rm -rf build "$(PROJECT)"
