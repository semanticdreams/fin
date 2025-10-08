.PHONY: build install release

build:
	flutter build apk --release

install: 
	adb install -r build/app/outputs/flutter-apk/app-release.apk

release:
	@last_tag=$$(git tag --list 'v*' | sort -V | tail -n1); \
	if [ -z "$$last_tag" ]; then \
		new_version="v1"; \
	else \
		num=$$(echo $$last_tag | sed 's/^v//'); \
		new_num=$$((num + 1)); \
		new_version="v$${new_num}"; \
	fi; \
	echo "Creating new annotated tag $$new_version"; \
	git tag -a $$new_version -m "$$new_version"; \
	git push origin $$new_version
