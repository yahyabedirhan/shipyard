# shipyard: build, test, bundle, sign and install the menu bar app with
# SwiftPM alone (no Xcode project).
#
#   make            build the app (release)
#   make test       run the tests (swift test)
#   make bundle     build/Shipyard.app, menu-bar-only (LSUIElement), ad-hoc signed
#   make install    bundle, then replace /Applications/Shipyard.app and open it
#   make release    test, bundle, and zip it as build/Shipyard-<version>-macos.zip
#   make run        run the executable from .build, without a bundle
#   make icon       redraw Packaging/Icon/AppIcon.icns from make-icon.swift
#   make clean

APP         := Shipyard
# The version lives in one place, the core; the bundle is stamped with it.
VERSION     := $(shell sed -n 's/.*static let current = "\(.*\)".*/\1/p' Sources/ShipyardCore/Version.swift)

BUILD_DIR   := build
APP_BUNDLE  := $(BUILD_DIR)/$(APP).app
CONTENTS    := $(APP_BUNDLE)/Contents
ZIP         := $(BUILD_DIR)/$(APP)-$(VERSION)-macos.zip
INSTALL_DIR := /Applications
ICON        := Packaging/Icon/AppIcon.icns
ICONSET     := $(BUILD_DIR)/AppIcon.iconset

# With the Command Line Tools alone (no Xcode), swift test can't find the
# Testing framework the tests use: point the compiler and the test runner at
# the copy the Command Line Tools ship. With Xcode (CI) nothing is needed.
DEVELOPER_DIR := $(shell xcode-select -p 2>/dev/null)
ifneq (,$(findstring CommandLineTools,$(DEVELOPER_DIR)))
TESTING_FRAMEWORKS := $(DEVELOPER_DIR)/Library/Developer/Frameworks
TESTING_LIBRARIES  := $(DEVELOPER_DIR)/Library/Developer/usr/lib
TEST_FLAGS := -Xswiftc -F -Xswiftc $(TESTING_FRAMEWORKS) \
	-Xlinker -F -Xlinker $(TESTING_FRAMEWORKS) \
	-Xlinker -rpath -Xlinker $(TESTING_FRAMEWORKS) \
	-Xlinker -rpath -Xlinker $(TESTING_LIBRARIES)
endif

.PHONY: all build test bundle install release run icon clean

all: build

build:
	swift build -c release --product $(APP)

test:
	swift test $(TEST_FLAGS)

run:
	swift run $(APP)

bundle: build
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources
	cp "$$(swift build -c release --show-bin-path)/$(APP)" $(CONTENTS)/MacOS/$(APP)
	sed 's/__VERSION__/$(VERSION)/g' Packaging/Info.plist > $(CONTENTS)/Info.plist
	cp $(ICON) $(CONTENTS)/Resources/AppIcon.icns
	@printf 'APPL????' > $(CONTENTS)/PkgInfo
	@# Ad-hoc: no Developer ID until the public launch. Signing the whole
	@# bundle gives it the stable identity notifications and login items need.
	codesign --force --sign - --timestamp=none $(APP_BUNDLE)
	codesign --verify --strict $(APP_BUNDLE)
	@echo "bundled $(APP_BUNDLE) ($(VERSION))"

install: bundle
	@pkill -x $(APP) 2>/dev/null || true
	@while pgrep -x $(APP) >/dev/null; do sleep 0.2; done
	rm -rf $(INSTALL_DIR)/$(APP).app
	ditto $(APP_BUNDLE) $(INSTALL_DIR)/$(APP).app
	@echo "installed $(INSTALL_DIR)/$(APP).app"
	open $(INSTALL_DIR)/$(APP).app

release: test bundle
	@rm -f $(ZIP)
	@# Without extended attributes: they're this Mac's (com.apple.provenance),
	@# and the signature doesn't need them. So unzip leaves no __MACOSX folder.
	cd $(BUILD_DIR) && ditto -c -k --keepParent --norsrc --noextattr --noacl $(APP).app $(notdir $(ZIP))
	@shasum -a 256 $(ZIP)

# The icon is committed, so bundling doesn't redraw it; run this after
# changing make-icon.swift.
icon:
	swift Packaging/Icon/make-icon.swift $(ICONSET)
	iconutil -c icns $(ICONSET) -o $(ICON)
	@rm -rf $(ICONSET)

clean:
	rm -rf $(BUILD_DIR) .build
