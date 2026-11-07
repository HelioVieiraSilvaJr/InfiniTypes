APP_NAME    := InfinidimTypes
DERIVED     := build/DerivedData
APP         := $(DERIVED)/Build/Products/Debug/$(APP_NAME).app
RELEASE_APP := $(DERIVED)/Build/Products/Release/$(APP_NAME).app
VERSION     := $(shell sed -nE 's/^ *MARKETING_VERSION: "(.*)"/\1/p' project.yml)
DMG         := dist/$(APP_NAME)-$(VERSION).dmg

TEAM_ID        := D93D4Z3ZT7
# Perfil criado com `xcrun notarytool store-credentials` (ver docs/DISTRIBUICAO.md)
NOTARY_PROFILE ?= InfinidimTypes
DEVELOPER_ID    = $(shell security find-identity -v -p codesigning | grep "Developer ID Application" | grep "($(TEAM_ID))" | head -1 | awk '{print $$2}')

.PHONY: project build test run release dmg package notarize clean

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

release: project
	xcodebuild -project $(APP_NAME).xcodeproj -scheme $(APP_NAME) -configuration Release \
		-destination 'platform=macOS,arch=arm64' -derivedDataPath $(DERIVED) -quiet build

# Imagem de disco para instalar em outro Mac: abrir e arrastar o app para Aplicativos.
# Assinada com o certificado de desenvolvimento: no outro Mac, o primeiro uso pede "Abrir Mesmo Assim".
dmg: release package

package:
	rm -rf build/dmg && mkdir -p build/dmg dist
	ditto $(RELEASE_APP) build/dmg/$(APP_NAME).app
	ln -s /Applications build/dmg/Applications
	hdiutil create -volname "$(APP_NAME) $(VERSION)" -srcfolder build/dmg -ov -format UDZO -quiet $(DMG)
	@echo "Gerado: $(DMG)"

# Versão para distribuir: assinada com Developer ID, notarizada pela Apple e com o ticket grampeado
# (staple) no .dmg, para abrir em qualquer Mac sem liberação manual.
notarize: project
	@test -n "$(DEVELOPER_ID)" || { echo "Falta o certificado \"Developer ID Application\" do time $(TEAM_ID) no Keychain (ver docs/DISTRIBUICAO.md)."; exit 1; }
	@xcrun notarytool history --keychain-profile $(NOTARY_PROFILE) >/dev/null 2>&1 || { echo "Falta o perfil de notarização \"$(NOTARY_PROFILE)\" (ver docs/DISTRIBUICAO.md)."; exit 1; }
	xcodebuild -project $(APP_NAME).xcodeproj -scheme $(APP_NAME) -configuration Release \
		-destination 'platform=macOS,arch=arm64' -derivedDataPath $(DERIVED) \
		CODE_SIGN_IDENTITY="Developer ID Application" OTHER_CODE_SIGN_FLAGS=--timestamp -quiet build
	codesign --verify --strict $(RELEASE_APP)
	$(MAKE) package
	codesign --sign "$(DEVELOPER_ID)" --timestamp $(DMG)
	xcrun notarytool submit $(DMG) --keychain-profile $(NOTARY_PROFILE) --wait
	xcrun stapler staple $(DMG)
	spctl --assess --type open --context context:primary-signature -vv $(DMG)
	@echo "Notarizado: $(DMG)"

clean:
	rm -rf build dist $(APP_NAME).xcodeproj
