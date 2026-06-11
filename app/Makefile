APP_NAME := gunk
PRODUCT_NAME := GunkApp
CONFIGURATION ?= debug
BUILD_DIR := build
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
EXECUTABLE := .build/$(CONFIGURATION)/$(PRODUCT_NAME)
ENGINE_DIR := ../engine
ENGINE_BINARY := $(ENGINE_DIR)/dist/gunk-engine
SIGN_IDENTITY ?= -
CODESIGN_FLAGS ?=

.PHONY: build test app verify-app rebuild clean engine icon

build:
	swift build

test:
	swift test

# Regenerates the app icon from `BrandMark` (T-7.5): renders the iconutil
# PNG set via the dev-only GUNK_RENDER_APPICON mode, rebuilds AppIcon.icns,
# and refreshes the AppIcon.appiconset copies.
ICONSET_DIR := $(BUILD_DIR)/AppIcon.iconset
APPICONSET_DIR := Sources/GunkApp/Resources/Assets.xcassets/AppIcon.appiconset

icon: build
	rm -rf "$(ICONSET_DIR)"
	mkdir -p "$(ICONSET_DIR)"
	GUNK_RENDER_APPICON="$(ICONSET_DIR)" "$(EXECUTABLE)"
	iconutil -c icns "$(ICONSET_DIR)" -o AppIcon.icns
	cp "$(ICONSET_DIR)"/icon_*.png "$(APPICONSET_DIR)/"

# Builds the cross-platform decomposition engine as a self-contained Bun binary.
engine:
	cd "$(ENGINE_DIR)" && bun install --frozen-lockfile && bun run build

app: build engine
	rm -rf "$(APP_BUNDLE)"
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS" "$(APP_BUNDLE)/Contents/Resources"
	cp "$(EXECUTABLE)" "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"
	cp "$(ENGINE_BINARY)" "$(APP_BUNDLE)/Contents/Resources/gunk-engine"
	cp "AppIcon.icns" "$(APP_BUNDLE)/Contents/Resources/AppIcon.icns"
	printf '%s\n' \
		'<?xml version="1.0" encoding="UTF-8"?>' \
		'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
		'<plist version="1.0">' \
		'<dict>' \
		'  <key>CFBundleDevelopmentRegion</key>' \
		'  <string>en</string>' \
		'  <key>CFBundleExecutable</key>' \
		'  <string>$(APP_NAME)</string>' \
		'  <key>CFBundleIconFile</key>' \
		'  <string>AppIcon</string>' \
		'  <key>CFBundleIdentifier</key>' \
		'  <string>app.gunk.GunkApp</string>' \
		'  <key>CFBundleInfoDictionaryVersion</key>' \
		'  <string>6.0</string>' \
		'  <key>CFBundleName</key>' \
		'  <string>gunk</string>' \
		'  <key>CFBundlePackageType</key>' \
		'  <string>APPL</string>' \
		'  <key>CFBundleShortVersionString</key>' \
		'  <string>0.0.1</string>' \
		'  <key>CFBundleVersion</key>' \
		'  <string>1</string>' \
		'  <key>LSMinimumSystemVersion</key>' \
		'  <string>26.0</string>' \
		'  <key>LSUIElement</key>' \
		'  <false/>' \
		'  <key>NSHighResolutionCapable</key>' \
		'  <true/>' \
		'  <key>NSQuitAlwaysKeepsWindows</key>' \
		'  <false/>' \
		'</dict>' \
		'</plist>' > "$(APP_BUNDLE)/Contents/Info.plist"
	codesign --force --sign "$(SIGN_IDENTITY)" $(CODESIGN_FLAGS) "$(APP_BUNDLE)"
	$(MAKE) verify-app

verify-app:
	test -x "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"
	test -x "$(APP_BUNDLE)/Contents/Resources/gunk-engine"
	test -s "$(APP_BUNDLE)/Contents/Resources/AppIcon.icns"
	plutil -lint "$(APP_BUNDLE)/Contents/Info.plist"
	codesign --verify --strict "$(APP_BUNDLE)"

rebuild: clean app

clean:
	rm -rf .build "$(BUILD_DIR)"
