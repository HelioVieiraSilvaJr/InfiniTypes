APP_NAME := InfinidimTypes
DERIVED  := build/DerivedData
APP      := $(DERIVED)/Build/Products/Debug/$(APP_NAME).app

.PHONY: project build test run clean

# Gera o .xcodeproj a partir do project.yml
project:
	xcodegen generate --quiet

build: project
	xcodebuild -project $(APP_NAME).xcodeproj -scheme $(APP_NAME) -configuration Debug \
		-destination 'platform=macOS,arch=arm64' -derivedDataPath $(DERIVED) -quiet build

test: project
	xcodebuild -project $(APP_NAME).xcodeproj -scheme $(APP_NAME) -configuration Debug \
		-destination 'platform=macOS,arch=arm64' -derivedDataPath $(DERIVED) -quiet test

# Encerra a instância anterior e abre o build novo (caminho fixo, para o macOS manter as permissões)
run: build
	-pkill -x $(APP_NAME)
	@while pgrep -x $(APP_NAME) >/dev/null; do sleep 0.2; done
	@sleep 0.5 # o LaunchServices demora um pouco para registrar o encerramento
	open $(APP)

clean:
	rm -rf build $(APP_NAME).xcodeproj
