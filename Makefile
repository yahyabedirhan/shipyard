# shipyard: build, test, bundle, sign and install the menu bar app with
# SwiftPM alone (no Xcode project).
#
#   make            build the app (release)
#   make test       run the tests (swift test)
#   make bundle     build/Shipyard.app, menu-bar-only (LSUIElement), with the shipyard CLI, signed with
#                   this Mac's local identity when it has one (make signing-identity), else ad-hoc
#   make signing-identity  make this Mac's local signing identity, once
#   make install    bundle, then replace /Applications/Shipyard.app and open it
#   make release    test, bundle, and zip it as build/Shipyard-<version>-macos.zip
#                   (bump Version.swift first; README's Development section has the release order)
#   make run        run the executable from .build, without a bundle
#   make icon       redraw Packaging/Icon/AppIcon.icns from make-icon.swift (ICON=khaki-green)
#   make icon-alternates  redraw the other variants into Packaging/Icon/alternates/
#   make icon-exploration redraw the minimal sailboat options and their comparison sheet
#   make clean

APP         := Shipyard
# The `shipyard` command line agents send pings with (ADR 0004). Its
# product is shipyard-cli: on a case-insensitive disk `shipyard` would be the
# app's `Shipyard`, which is also why the bundle keeps it in Contents/Helpers,
# not beside the app in Contents/MacOS.
CLI         := shipyard-cli
# The version lives in one place, the core; the bundle is stamped with it.
VERSION     := $(shell sed -n 's/.*static let current = "\(.*\)".*/\1/p' Sources/ShipyardCommand/Version.swift)

BUILD_DIR   := build
APP_BUNDLE  := $(BUILD_DIR)/$(APP).app
CONTENTS    := $(APP_BUNDLE)/Contents
ZIP         := $(BUILD_DIR)/$(APP)-$(VERSION)-macos.zip
INSTALL_DIR := /Applications
ICON_FILE   := Packaging/Icon/AppIcon.icns
ICONSET     := $(BUILD_DIR)/AppIcon.iconset
# The variant make-icon.swift draws for the app: khaki-green (shipyard's logo),
# olive-khaki, origami, sailboat, night or sunset.
ICON        ?= khaki-green
ALTERNATES  := olive-khaki origami sailboat night sunset

# A local signing identity keeps the app the same app to the Keychain from
# one build to the next. Ad-hoc signing makes each build a new app, so
# macOS asks again for the GitHub and Notion tokens after every install.
# `make signing-identity` makes a self-signed certificate in a keychain of
# its own, once per Mac; `make bundle` signs with it when it's there. The
# certificate is trusted by nothing, so its key guards nothing but this
# Mac's builds, and its keychain's password can sit here. A release is
# always signed ad-hoc: its zip is for every Mac.
SIGN_NAME     := Shipyard Local Signing
SIGN_KEYCHAIN := $(HOME)/Library/Keychains/shipyard-signing.keychain-db
SIGN_PASSWORD := shipyard-signing
SIGN_MODE     ?= local
# make-icon.swift is compiled with the app's sailboat path and logo, so the
# icon, the menu bar item and the badge draw one figure in the same colours. swiftc runs top-level code only
# from a main.swift, so the script is copied in under that name.
ICON_TOOL   := $(BUILD_DIR)/make-icon/make-icon
BRAND       := Sources/ShipyardApp/Brand/Sailboat.swift Sources/ShipyardApp/Brand/Logo.swift

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
# The Command Line Tools ship no prebuilt SDK modules either, so a new
# checkout's first build compiles Swift, Foundation, SwiftUI and the rest from
# their interfaces (about 40 s of a 56 s clean build). One module cache shared
# by every checkout and worktree pays that once. Its entries are keyed by the
# compiler, the SDK and the flags, so an update builds new ones, and concurrent
# builds share it through the compiler's own locks.
MODULE_CACHE := $(HOME)/Library/Caches/shipyard/ModuleCache
SWIFT_FLAGS  := -Xswiftc -module-cache-path -Xswiftc $(MODULE_CACHE)
endif

.PHONY: all build test bundle install release signing-identity run icon icon-alternates icon-exploration agent-logos clean

all: build

build:
	swift build -c release --product $(APP) $(SWIFT_FLAGS)
	swift build -c release --product $(CLI) $(SWIFT_FLAGS)

test:
	swift test $(SWIFT_FLAGS) $(TEST_FLAGS)

run:
	swift run $(APP) $(SWIFT_FLAGS)

bundle: build
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Helpers $(CONTENTS)/Resources
	cp "$$(swift build -c release --show-bin-path)/$(APP)" $(CONTENTS)/MacOS/$(APP)
	cp "$$(swift build -c release --show-bin-path)/$(CLI)" $(CONTENTS)/Helpers/shipyard
	sed 's/__VERSION__/$(VERSION)/g' Packaging/Info.plist > $(CONTENTS)/Info.plist
	cp $(ICON_FILE) $(CONTENTS)/Resources/AppIcon.icns
	@# The app's SwiftPM resources (the agents' logos), where AgentLogoImage
	@# looks: in Resources, since a bundle at the app's root breaks its signature.
	cp -R "$$(swift build -c release --show-bin-path)/$(APP)_$(APP)App.bundle" $(CONTENTS)/Resources/
	@# The logos' MIT notices travel with every copy of them.
	cp LICENSE THIRD-PARTY-NOTICES.md $(CONTENTS)/Resources/
	@printf 'APPL????' > $(CONTENTS)/PkgInfo
	@# No Developer ID until the public launch: the local identity on a Mac
	@# that has one (see SIGN_NAME), ad-hoc otherwise and for a release.
	@# Signing the whole bundle gives it the stable identity notifications
	@# and login items need. The CLI is signed first: the bundle's
	@# signature seals nested code.
	@identity=-; \
	if [ "$(SIGN_MODE)" = local ] && [ -f "$(SIGN_KEYCHAIN)" ] \
		&& security unlock-keychain -p "$(SIGN_PASSWORD)" "$(SIGN_KEYCHAIN)" \
		&& security find-identity -p codesigning "$(SIGN_KEYCHAIN)" | grep -q "$(SIGN_NAME)"; then \
		identity="$(SIGN_NAME)"; \
	fi; \
	echo "signing with $$identity"; \
	codesign --force --sign "$$identity" --timestamp=none $(CONTENTS)/Helpers/shipyard && \
	codesign --force --sign "$$identity" --timestamp=none $(APP_BUNDLE)
	codesign --verify --strict $(APP_BUNDLE)
	@echo "bundled $(APP_BUNDLE) ($(VERSION))"

# macOS imports only a PKCS#12 made with the legacy algorithms: OpenSSL 3
# needs -legacy for them, LibreSSL makes them already.
signing-identity:
	@if [ -f "$(SIGN_KEYCHAIN)" ]; then echo "$(SIGN_KEYCHAIN) exists already"; exit 0; fi; \
	set -e; dir=$$(mktemp -d); \
	printf '[req]\ndistinguished_name = dn\nx509_extensions = ext\nprompt = no\n[dn]\nCN = $(SIGN_NAME)\n[ext]\nkeyUsage = critical, digitalSignature\nextendedKeyUsage = critical, codeSigning\nbasicConstraints = critical, CA:false\n' > $$dir/cert.cnf; \
	openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -keyout $$dir/key.pem -out $$dir/cert.pem -config $$dir/cert.cnf 2>/dev/null; \
	openssl pkcs12 -export -legacy -inkey $$dir/key.pem -in $$dir/cert.pem -out $$dir/id.p12 -passout pass:$(SIGN_PASSWORD) 2>/dev/null \
		|| openssl pkcs12 -export -inkey $$dir/key.pem -in $$dir/cert.pem -out $$dir/id.p12 -passout pass:$(SIGN_PASSWORD); \
	security create-keychain -p "$(SIGN_PASSWORD)" "$(SIGN_KEYCHAIN)"; \
	security set-keychain-settings "$(SIGN_KEYCHAIN)"; \
	security unlock-keychain -p "$(SIGN_PASSWORD)" "$(SIGN_KEYCHAIN)"; \
	security import $$dir/id.p12 -k "$(SIGN_KEYCHAIN)" -P "$(SIGN_PASSWORD)" -T /usr/bin/codesign >/dev/null; \
	security set-key-partition-list -S apple-tool:,apple: -s -k "$(SIGN_PASSWORD)" "$(SIGN_KEYCHAIN)" >/dev/null; \
	security list-keychains -d user -s $$(security list-keychains -d user | tr -d '"') "$(SIGN_KEYCHAIN)"; \
	rm -f $$dir/cert.cnf $$dir/key.pem $$dir/cert.pem $$dir/id.p12; rmdir $$dir; \
	echo "made $(SIGN_NAME) in $(SIGN_KEYCHAIN)"

install: bundle
	@# Only this user's copy; one that hasn't quit after about 10 s is killed.
	@pkill -u "$$USER" -x $(APP) 2>/dev/null || true
	@tries=0; while pgrep -u "$$USER" -x $(APP) >/dev/null; do \
		if [ $$tries -ge 50 ]; then \
			echo "$(APP) didn't quit within 10 s; killing it"; \
			pkill -9 -u "$$USER" -x $(APP) 2>/dev/null || true; \
			sleep 0.5; break; \
		fi; \
		tries=$$((tries + 1)); sleep 0.2; \
	done
	rm -rf $(INSTALL_DIR)/$(APP).app
	ditto $(APP_BUNDLE) $(INSTALL_DIR)/$(APP).app
	@echo "installed $(INSTALL_DIR)/$(APP).app"
	open $(INSTALL_DIR)/$(APP).app

# A release is for every Mac: ad-hoc, whatever this Mac has.
release: SIGN_MODE := adhoc
release: test bundle
	@rm -f $(ZIP)
	@# Without extended attributes: they're this Mac's (com.apple.provenance),
	@# and the signature doesn't need them. So unzip leaves no __MACOSX folder.
	cd $(BUILD_DIR) && ditto -c -k --keepParent --norsrc --noextattr --noacl $(APP).app $(notdir $(ZIP))
	@shasum -a 256 $(ZIP)

# The icon is committed, so bundling doesn't redraw it; run this after
# changing make-icon.swift, or with ICON=<variant> to switch the app's icon.
$(ICON_TOOL): Packaging/Icon/make-icon.swift $(BRAND)
	@mkdir -p $(dir $@)
	cp Packaging/Icon/make-icon.swift $(dir $@)main.swift
	swiftc -o $@ $(dir $@)main.swift $(BRAND)

icon: $(ICON_TOOL)
	$(ICON_TOOL) $(ICONSET) --variant $(ICON)
	iconutil -c icns $(ICONSET) -o $(ICON_FILE)
	@rm -rf $(ICONSET)

# The variants the app doesn't use, kept to switch to: an .icns and a 512 pt
# preview of each in Packaging/Icon/alternates/, committed.
icon-alternates: $(ICON_TOOL)
	@mkdir -p Packaging/Icon/alternates
	@for variant in $(ALTERNATES); do \
		$(ICON_TOOL) $(ICONSET) --variant $$variant || exit 1; \
		iconutil -c icns $(ICONSET) -o Packaging/Icon/alternates/$$variant.icns || exit 1; \
		cp $(ICONSET)/icon_512x512.png Packaging/Icon/alternates/$$variant.png; \
		echo "drew Packaging/Icon/alternates/$$variant.icns"; \
	done
	@rm -rf $(ICONSET)

# The minimal sailboat options, not yet the app's icon: a 512 pt PNG of each and
# a comparison sheet (with the menu bar item and the badge) in the exploration folder.
icon-exploration: $(ICON_TOOL)
	$(ICON_TOOL) --exploration assets/images/app-icon/exploration

# Each known agent's logo, kept as its maker's SVG in assets/images/agent-logos/
# (sources in docs/references/agent-icons.md), converted to the vector PDF the
# app bundles: macOS 14 can't be relied on to load SVG. The PDFs are
# committed, so bundling doesn't need librsvg; run this after changing an SVG
# (brew install librsvg).
AGENT_LOGO_SVGS := $(wildcard assets/images/agent-logos/*.svg)
AGENT_LOGOS     := Sources/ShipyardApp/Resources/AgentLogos

agent-logos:
	@mkdir -p $(AGENT_LOGOS)
	@for svg in $(AGENT_LOGO_SVGS); do \
		pdf=$(AGENT_LOGOS)/$$(basename $$svg .svg).pdf; \
		rsvg-convert --format pdf --output $$pdf $$svg || exit 1; \
		echo "drew $$pdf"; \
	done

clean:
	rm -rf $(BUILD_DIR) .build
