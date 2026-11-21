.PHONY: deps help

help:
	@echo "make deps   Install required packages using your distro's package manager"

# Detects the package manager and installs: WireGuard tools, iproute2, sudo,
# util-linux (setpriv), and curl. Vesktop itself is not installed; see README.
deps:
	@set -e; \
	if [ "$$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi; \
	if command -v pacman >/dev/null 2>&1; then \
	  echo "Detected pacman (Arch-based)"; \
	  $$SUDO pacman -S --needed wireguard-tools iproute2 sudo util-linux curl; \
	elif command -v apt-get >/dev/null 2>&1; then \
	  echo "Detected apt (Debian/Ubuntu-based)"; \
	  $$SUDO apt-get update; \
	  $$SUDO apt-get install -y wireguard-tools iproute2 sudo util-linux curl; \
	elif command -v dnf >/dev/null 2>&1; then \
	  echo "Detected dnf (Fedora/RHEL-based)"; \
	  $$SUDO dnf install -y wireguard-tools iproute sudo util-linux curl; \
	elif command -v zypper >/dev/null 2>&1; then \
	  echo "Detected zypper (openSUSE)"; \
	  $$SUDO zypper --non-interactive install wireguard-tools iproute2 sudo util-linux curl; \
	elif command -v apk >/dev/null 2>&1; then \
	  echo "Detected apk (Alpine)"; \
	  $$SUDO apk add wireguard-tools iproute2 sudo util-linux curl; \
	elif command -v xbps-install >/dev/null 2>&1; then \
	  echo "Detected xbps (Void)"; \
	  $$SUDO xbps-install -S wireguard-tools iproute2 sudo util-linux curl; \
	else \
	  echo "No supported package manager found. Install manually (see README)." >&2; \
	  exit 1; \
	fi; \
	echo "Done. Vesktop is not installed by this target; see README."
