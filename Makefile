.PHONY: build app install clean

APP_NAME = ReviewSetup
BUNDLE = $(APP_NAME).app
CONTENTS = $(BUNDLE)/Contents
MACOS = $(CONTENTS)/MacOS
RESOURCES = $(CONTENTS)/Resources

build:
	swift build -c release

app: build
	mkdir -p $(MACOS)
	mkdir -p $(RESOURCES)
	cp .build/release/review-setup $(MACOS)/
	cp Resources/Info.plist $(CONTENTS)/

install: app
	rm -rf ~/Applications/$(BUNDLE)
	cp -R $(BUNDLE) ~/Applications/

clean:
	rm -rf $(BUNDLE)
	swift package clean
