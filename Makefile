.PHONY: build install

build:
	flutter build apk --release

install: 
	adb install -r build/app/outputs/flutter-apk/app-release.apk
