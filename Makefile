.PHONY: all build install uninstall clean release

all: build

build:
	@bash scripts/build.sh

install: build
	@sudo rm -rf "/Applications/Legion RGB.app"
	@sudo cp -R "build/Legion RGB.app" "/Applications/Legion RGB.app"
	@sudo install -m 755 build/legion-rgb /usr/local/bin/legion-rgb
	@echo "Installed /Applications/Legion RGB.app and /usr/local/bin/legion-rgb"

uninstall:
	@sudo rm -rf "/Applications/Legion RGB.app" /usr/local/bin/legion-rgb
	@echo "Removed Legion RGB.app and legion-rgb"

release: build
	@cd build && ditto -c -k --sequesterRsrc --keepParent "Legion RGB.app" "Legion-RGB-macOS-app.zip"
	@cd build && zip -q "legion-rgb-cli-macos-x86_64.zip" legion-rgb
	@echo "Release archives ready in build/"

clean:
	@rm -rf build
