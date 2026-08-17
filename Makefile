PLUGIN_ID := io.github.d3vw.sinbar
PLUGIN_DIR := $(HOME)/.config/omarchy/plugins/$(PLUGIN_ID)
BRIDGE := bin/sinbar-bridge

.PHONY: build test validate check install-local uninstall-local clean

build:
	go build -trimpath -ldflags='-s -w' -o $(BRIDGE) ./cmd/sinbar-bridge

test:
	go test ./...

validate:
	omarchy plugin validate "$(CURDIR)"
	qmllint -I "$(OMARCHY_PATH)/shell" Panel.qml Service.qml

check: test validate build

install-local: check
	mkdir -p "$(PLUGIN_DIR)/bin"
	cp "$(BRIDGE)" "$(PLUGIN_DIR)/bin/.sinbar-bridge.new"
	chmod 755 "$(PLUGIN_DIR)/bin/.sinbar-bridge.new"
	mv -f "$(PLUGIN_DIR)/bin/.sinbar-bridge.new" "$(PLUGIN_DIR)/bin/sinbar-bridge"
	cp manifest.json Panel.qml Service.qml Model.js README.md LICENSE "$(PLUGIN_DIR)/"
	omarchy-shell shell rescanPlugins
	@for i in 1 2 3 4 5; do \
		omarchy plugin list --json | jq -e '.[] | select(.id == "$(PLUGIN_ID)")' >/dev/null && break; \
		sleep 0.4; \
	done
	omarchy plugin enable $(PLUGIN_ID)

uninstall-local:
	omarchy plugin remove $(PLUGIN_ID)

clean:
	rm -f $(BRIDGE)
