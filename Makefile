PREFIX      ?= $(HOME)/.local
BIN_DIR     := $(PREFIX)/bin
APP_DIR     := $(HOME)/.local/share/applications
BIN_NAME    := vesktop-bypass
DESKTOP     := $(APP_DIR)/vesktop-netns.desktop
CONF_DIR    := $(HOME)/.config/vesktop-netns
CONF_FILE   := $(CONF_DIR)/wg.conf
# Path to your WireGuard config, used by "make install": make install CONF=~/Downloads/x.conf
CONF        ?=
# Extra arguments for run/test, for example: make run ARGS="--split-voice"
ARGS        ?=

.PHONY: help deps run test split install uninstall

help:
	@echo "make deps        Install required packages using your distro's package manager"
	@echo "make run         Run Vesktop through the tunnel (ARGS=... for options)"
	@echo "make split       Run Vesktop with direct voice/video UDP (--split-voice)"
	@echo "make test        Print the public IP seen through the tunnel"
	@echo "make install     Save your WireGuard config and add the launcher entry (CONF=path/to/file.conf)"
	@echo "make uninstall   Remove the launcher entry and installed script"

run:
	./vesktop-bypass.sh $(ARGS)

split:
	./vesktop-bypass.sh --split-voice $(ARGS)

test:
	./vesktop-bypass.sh --test $(ARGS)

# Saves the WireGuard config, installs the script to ~/.local/bin, and adds a
# desktop entry to the user's application menu. The entry shows a graphical
# password prompt (zenity or kdialog) and logs to ~/.local/state/vesktop-netns/last.log.
install:
	@if [ -n "$(CONF)" ]; then \
	  [ -f "$(CONF)" ] || { echo "Config not found: $(CONF)" >&2; exit 1; }; \
	  install -d -m 700 "$(CONF_DIR)"; \
	  install -m 600 "$(CONF)" "$(CONF_FILE)"; \
	  echo "Saved config to $(CONF_FILE)"; \
	elif [ -f "$(CONF_FILE)" ]; then \
	  chmod 600 "$(CONF_FILE)"; \
	  echo "Using existing config $(CONF_FILE)"; \
	else \
	  echo "No WireGuard config found." >&2; \
	  echo "Run: make install CONF=path/to/your-file.conf" >&2; \
	  echo "See docs/details.md for how to get a free file." >&2; \
	  exit 1; \
	fi
	install -d -m 755 "$(BIN_DIR)" "$(APP_DIR)"
	install -m 755 vesktop-bypass.sh "$(BIN_DIR)/$(BIN_NAME)"
	@printf '%s\n' \
	  '[Desktop Entry]' \
	  'Type=Application' \
	  'Name=Vesktop Netns' \
	  'Comment=Vesktop routed through a WireGuard tunnel' \
	  'Exec=$(BIN_DIR)/$(BIN_NAME)' \
	  'Icon=vesktop' \
	  'Terminal=false' \
	  'Categories=Network;InstantMessaging;Chat;' \
	  'Keywords=Discord;Vesktop;VPN;WireGuard;' \
	  > "$(DESKTOP)"
	@chmod 644 "$(DESKTOP)"
	@command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$(APP_DIR)" || true
	@echo "Installed. Search for 'Vesktop Netns' in your app launcher."

# Keeps your saved config. Delete $(CONF_DIR) yourself to remove it.
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
	  $$SUDO pacman -S --needed wireguard-tools iproute2 sudo util-linux curl zenity nftables procps-ng; \
	elif command -v apt-get >/dev/null 2>&1; then \
	  echo "Detected apt (Debian/Ubuntu-based)"; \
	  $$SUDO apt-get update; \
	  $$SUDO apt-get install -y wireguard-tools iproute2 sudo util-linux curl zenity nftables procps; \
	elif command -v dnf >/dev/null 2>&1; then \
	  echo "Detected dnf (Fedora/RHEL-based)"; \
	  $$SUDO dnf install -y wireguard-tools iproute sudo util-linux curl zenity nftables procps-ng; \
	elif command -v zypper >/dev/null 2>&1; then \
	  echo "Detected zypper (openSUSE)"; \
	  $$SUDO zypper --non-interactive install wireguard-tools iproute2 sudo util-linux curl zenity nftables procps; \
	elif command -v apk >/dev/null 2>&1; then \
	  echo "Detected apk (Alpine)"; \
	  $$SUDO apk add wireguard-tools iproute2 sudo util-linux curl zenity nftables procps; \
	elif command -v xbps-install >/dev/null 2>&1; then \
	  echo "Detected xbps (Void)"; \
	  $$SUDO xbps-install -S wireguard-tools iproute2 sudo util-linux curl zenity nftables procps-ng; \
	else \
	  echo "No supported package manager found. Install manually (see README)." >&2; \
	  exit 1; \
	fi; \
	echo "Done. Vesktop is not installed by this target; see README."
