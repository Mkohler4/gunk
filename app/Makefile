APP_NAME := gunk
PRODUCT_NAME := GunkApp
CONFIGURATION ?= debug
BUILD_DIR := build
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
EXECUTABLE := .build/$(CONFIGURATION)/$(PRODUCT_NAME)

.PHONY: build test app rebuild clean

build:
	swift build

test:
	swift test

app: build
	rm -rf "$(APP_BUNDLE)"
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS" "$(APP_BUNDLE)/Contents/Resources"
	cp "$(EXECUTABLE)" "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"
	printf '%s\n' \
		'<?xml version="1.0" encoding="UTF-8"?>' \
		'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
		'<plist version="1.0">' \
		'<dict>' \
		'  <key>CFBundleDevelopmentRegion</key>' \
		'  <string>en</string>' \
		'  <key>CFBundleExecutable</key>' \
		'  <string>$(APP_NAME)</string>' \
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
		'  <string>14.0</string>' \
		'  <key>LSUIElement</key>' \
		'  <true/>' \
		'  <key>NSHighResolutionCapable</key>' \
		'  <true/>' \
		'</dict>' \
		'</plist>' > "$(APP_BUNDLE)/Contents/Info.plist"
	codesign --force --sign - "$(APP_BUNDLE)"

rebuild: clean app

clean:
	rm -rf .build "$(BUILD_DIR)"
