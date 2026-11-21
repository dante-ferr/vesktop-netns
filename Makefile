PREFIX      ?= $(HOME)/.local
BIN_DIR     := $(PREFIX)/bin
APP_DIR     := $(HOME)/.local/share/applications
BIN_NAME    := vesktop-bypass
DESKTOP     := $(APP_DIR)/vesktop-netns.desktop
# Extra arguments for run/test, for example: make run ARGS="--split-voice"
ARGS        ?=

.PHONY: help deps run test split install uninstall

help:
	@echo "make deps        Install required packages using your distro's package manager"
	@echo "make run         Run Vesktop through the tunnel (ARGS=... for options)"
	@echo "make split       Run Vesktop with direct voice/video UDP (--split-voice)"
	@echo "make test        Print the public IP seen through the tunnel"
	@echo "make install     Add 'Vesktop Netns' to the application launcher"
	@echo "make uninstall   Remove the launcher entry and installed script"

run:
	./vesktop-bypass.sh $(ARGS)

split:
	./vesktop-bypass.sh --split-voice $(ARGS)

test:
	./vesktop-bypass.sh --test $(ARGS)

# Installs the script to ~/.local/bin and a desktop entry to the user's
# application menu. The entry opens a terminal because sudo needs a password.
install:
	install -d -m 755 "$(BIN_DIR)" "$(APP_DIR)"
	install -m 755 vesktop-bypass.sh "$(BIN_DIR)/$(BIN_NAME)"
	@printf '%s\n' \
	  '[Desktop Entry]' \
	  'Type=Application' \
	  'Name=Vesktop Netns' \
	  'Comment=Vesktop routed through a WireGuard tunnel' \
	  'Exec=$(BIN_DIR)/$(BIN_NAME)' \
	  'Icon=vesktop' \
	  'Terminal=true' \
	  'Categories=Network;InstantMessaging;Chat;' \
	  'Keywords=Discord;Vesktop;VPN;WireGuard;' \
	  > "$(DESKTOP)"
	@chmod 644 "$(DESKTOP)"
	@command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$(APP_DIR)" || true
	@echo "Installed. Search for 'Vesktop Netns' in your app launcher."
	@echo "Config is read from ~/.config/vesktop-netns/wg.conf (see README)."

uninstall:
	rm -f "$(BIN_DIR)/$(BIN_NAME)" "$(DESKTOP)"
	@command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$(APP_DIR)" || true
	@echo "Removed."

# Detects the package manager and installs: WireGuard tools, iproute2, sudo,
# util-linux (setpriv), curl, and nftables (only used by --split-voice).
# Vesktop itself is not installed; see README.
deps:
	@set -e; \
	if [ "$$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi; \
	if command -v pacman >/dev/null 2>&1; then \
	  echo "Detected pacman (Arch-based)"; \
	  $$SUDO pacman -S --needed wireguard-tools iproute2 sudo util-linux curl nftables procps-ng; \
	elif command -v apt-get >/dev/null 2>&1; then \
	  echo "Detected apt (Debian/Ubuntu-based)"; \
	  $$SUDO apt-get update; \
	  $$SUDO apt-get install -y wireguard-tools iproute2 sudo util-linux curl nftables procps; \
	elif command -v dnf >/dev/null 2>&1; then \
	  echo "Detected dnf (Fedora/RHEL-based)"; \
	  $$SUDO dnf install -y wireguard-tools iproute sudo util-linux curl nftables procps-ng; \
	elif command -v zypper >/dev/null 2>&1; then \
	  echo "Detected zypper (openSUSE)"; \
	  $$SUDO zypper --non-interactive install wireguard-tools iproute2 sudo util-linux curl nftables procps; \
	elif command -v apk >/dev/null 2>&1; then \
	  echo "Detected apk (Alpine)"; \
	  $$SUDO apk add wireguard-tools iproute2 sudo util-linux curl nftables procps; \
	elif command -v xbps-install >/dev/null 2>&1; then \
	  echo "Detected xbps (Void)"; \
	  $$SUDO xbps-install -S wireguard-tools iproute2 sudo util-linux curl nftables procps-ng; \
	else \
	  echo "No supported package manager found. Install manually (see README)." >&2; \
	  exit 1; \
	fi; \
	echo "Done. Vesktop is not installed by this target; see README."
