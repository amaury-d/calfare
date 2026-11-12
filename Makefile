SHELL := /bin/bash
.DEFAULT_GOAL := app

INSTALL_DIR ?= $(HOME)/Applications
APP := build/Calflare.app
LABEL := com.calflare.agent

.PHONY: app install uninstall preview logs test check clean

app:
	@set -eu; \
	swift build -c release; \
	bin_dir="$$(swift build -c release --show-bin-path)"; \
	mkdir -p build; \
	stage="$$(mktemp -d "build/.calflare-build.XXXXXX")"; \
	trap 'rm -rf "$$stage"' EXIT; \
	app="$$stage/Calflare.app"; \
	mkdir -p "$$app/Contents/MacOS" "$$app/Contents/Resources"; \
	cp App/Info.plist "$$app/Contents/Info.plist"; \
	cp -R App/Resources/. "$$app/Contents/Resources/"; \
	cp "$$bin_dir/CalflareAgent" "$$bin_dir/CalflareOverlay" "$$app/Contents/MacOS/"; \
	codesign --force --sign - --identifier com.calflare.overlay "$$app/Contents/MacOS/CalflareOverlay"; \
	codesign --force --sign - "$$app"; \
	codesign --verify --deep --strict "$$app"; \
	rm -rf "$(APP)"; \
	mv "$$app" "$(APP)"; \
	echo "Built $(APP)"

install: app
	@set -eu; \
	app="$(INSTALL_DIR)/Calflare.app"; \
	agents="$$HOME/Library/LaunchAgents"; \
	logs="$$HOME/Library/Logs/Calflare"; \
	plist="$$agents/$(LABEL).plist"; \
	service="gui/$$(id -u)/$(LABEL)"; \
	mkdir -p "$(INSTALL_DIR)" "$$agents" "$$logs"; \
	if [ -e "$$app" ] && [ "$$(plutil -extract CFBundleIdentifier raw -o - "$$app/Contents/Info.plist" 2>/dev/null || true)" != "$(LABEL)" ]; then \
		echo "Refusing to replace an app that is not Calflare: $$app" >&2; exit 1; \
	fi; \
	if [ -e "$$plist" ] && [ "$$(plutil -extract Label raw -o - "$$plist" 2>/dev/null || true)" != "$(LABEL)" ]; then \
		echo "Refusing to replace an unrelated LaunchAgent: $$plist" >&2; exit 1; \
	fi; \
	stage="$$(mktemp -d "$(INSTALL_DIR)/.calflare-install.XXXXXX")"; \
	old_app=0; old_plist=0; new_app=0; new_plist=0; was_loaded=0; committed=0; \
	rollback() { \
		status=$$?; trap - EXIT; \
		if [ "$$committed" = 0 ]; then \
			if [ "$$new_plist" = 1 ] && launchctl print "$$service" >/dev/null 2>&1; then \
				launchctl bootout "$$service" || { echo "Could not stop the new service; backup retained at $$stage" >&2; exit 1; }; \
			fi; \
			[ "$$new_plist" = 0 ] || rm -f "$$plist"; \
			[ "$$new_app" = 0 ] || rm -rf "$$app"; \
			if [ "$$old_app" = 1 ]; then mv "$$stage/previous.app" "$$app" || { echo "Restore the app from $$stage/previous.app" >&2; exit 1; }; fi; \
			if [ "$$old_plist" = 1 ]; then mv "$$stage/previous.plist" "$$plist" || { echo "Restore the plist from $$stage/previous.plist" >&2; exit 1; }; fi; \
			if [ "$$was_loaded" = 1 ]; then launchctl bootstrap "gui/$$(id -u)" "$$plist" || echo "Could not restore the previous service: $$plist" >&2; fi; \
		fi; \
		rm -rf "$$stage"; exit "$$status"; \
	}; \
	trap rollback EXIT; \
	ditto "$(APP)" "$$stage/Calflare.app"; \
	cp App/$(LABEL).plist "$$stage/agent.plist"; \
	plutil -replace ProgramArguments.0 -string "$$app/Contents/MacOS/CalflareAgent" "$$stage/agent.plist"; \
	plutil -replace StandardOutPath -string "$$logs/stdout.log" "$$stage/agent.plist"; \
	plutil -replace StandardErrorPath -string "$$logs/stderr.log" "$$stage/agent.plist"; \
	plutil -lint "$$stage/agent.plist"; \
	if launchctl print "$$service" >/dev/null 2>&1; then launchctl bootout "$$service"; was_loaded=1; fi; \
	if [ -e "$$app" ]; then mv "$$app" "$$stage/previous.app"; old_app=1; fi; \
	if [ -e "$$plist" ]; then mv "$$plist" "$$stage/previous.plist"; old_plist=1; fi; \
	mv "$$stage/Calflare.app" "$$app"; new_app=1; \
	mv "$$stage/agent.plist" "$$plist"; new_plist=1; \
	launchctl enable "$$service"; \
	launchctl bootstrap "gui/$$(id -u)" "$$plist"; \
	committed=1; \
	echo "Installed and started $(LABEL) from $$app"; \
	echo "Grant Calflare access in System Settings > Privacy & Security > Calendars."

uninstall:
	@set -eu; \
	app="$(INSTALL_DIR)/Calflare.app"; \
	plist="$$HOME/Library/LaunchAgents/$(LABEL).plist"; \
	service="gui/$$(id -u)/$(LABEL)"; \
	if [ -e "$$app" ] && [ "$$(plutil -extract CFBundleIdentifier raw -o - "$$app/Contents/Info.plist" 2>/dev/null || true)" != "$(LABEL)" ]; then \
		echo "Refusing to remove an app that is not Calflare: $$app" >&2; exit 1; \
	fi; \
	if [ -e "$$plist" ] && [ "$$(plutil -extract Label raw -o - "$$plist" 2>/dev/null || true)" != "$(LABEL)" ]; then \
		echo "Refusing to remove an unrelated LaunchAgent: $$plist" >&2; exit 1; \
	fi; \
	if launchctl print "$$service" >/dev/null 2>&1; then launchctl bootout "$$service"; fi; \
	rm -f "$$plist"; rm -rf "$$app"; \
	echo "Removed Calflare. Configuration, state and logs were preserved."

preview: app
	@"$(APP)/Contents/MacOS/CalflareAgent" --test

logs:
	@tail -F "$(HOME)/Library/Logs/Calflare/stdout.log" "$(HOME)/Library/Logs/Calflare/stderr.log"

test:
	swift test

check: test app
	plutil -lint App/Info.plist App/$(LABEL).plist App/Resources/en.lproj/*.strings App/Resources/fr.lproj/*.strings
	codesign --verify --deep --strict --verbose=2 "$(APP)"
	test -x "$(APP)/Contents/MacOS/CalflareAgent"
	test -x "$(APP)/Contents/MacOS/CalflareOverlay"

clean:
	rm -rf .build "$(APP)"
