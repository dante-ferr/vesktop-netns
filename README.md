# vesktop-netns

Run [Vesktop](https://github.com/Vencord/Vesktop) through a WireGuard VPN without changing the rest of your network. Vesktop runs in its own Linux network namespace. Every packet leaves through the tunnel. Your browser, games, and other apps keep using your normal connection.

The namespace has no other network interface. If the tunnel drops, Vesktop goes offline instead of leaking your real IP address (a built-in kill switch).

## Quick start

1. Install the [dependencies](#1-install-dependencies).
2. Get a [WireGuard `.conf` file](#2-get-a-free-wireguard-conf-file).
3. Clone the repository and run it:

   ```sh
   git clone https://github.com/<your-user>/vesktop-netns.git
   cd vesktop-netns
   ./vesktop-bypass.sh ~/Downloads/your-file.conf
   ```

Enter your password when `sudo` asks. Vesktop opens. Close Vesktop to remove the namespace and tunnel.

## 1. Install dependencies

You need: `iproute2` (`ip`), `wireguard-tools` (`wg`, `wg-quick`), `sudo`, `util-linux` (`setpriv`), `curl` (only for `--test`), and Vesktop.

| Distro | Command |
| --- | --- |
| Arch, Manjaro, EndeavourOS | `sudo pacman -S wireguard-tools iproute2 sudo curl` |
| Debian, Ubuntu, Linux Mint | `sudo apt install wireguard-tools iproute2 sudo curl` |
| Fedora | `sudo dnf install wireguard-tools iproute sudo curl` |
| openSUSE | `sudo zypper install wireguard-tools iproute2 sudo curl` |

Your kernel needs WireGuard support. Kernel 5.6 and later include it.

Install Vesktop from your package manager, the AUR (`vesktop`), or Flatpak:

```sh
flatpak install flathub dev.vencord.Vesktop
```

The script finds `vesktop` in your `PATH` first, then the Flatpak. To use another command, set `VESKTOP_CMD`.

## 2. Get a free WireGuard `.conf` file

Pick one option.

**Proton VPN (free plan, no card required)**

1. Create an account at [protonvpn.com](https://protonvpn.com).
2. Open **Downloads** > **WireGuard configuration**.
3. Select **GNU/Linux**, choose a free server, and click **Create**.
4. Download the `.conf` file.

**Cloudflare WARP (free) with `wgcf`**

1. Install [`wgcf`](https://github.com/ViRb3/wgcf) (`pacman -S wgcf` on Arch, or download a release).
2. Run `wgcf register`, then `wgcf generate`.
3. Use the generated `wgcf-profile.conf`.

WARP is not a privacy VPN, but it works as a free bypass for blocked access.

You can also use any provider that exports a standard WireGuard config (Mullvad, IVPN, your own server). See `wg.conf.example` for the expected format.

## 3. Save the config (optional)

You can pass the file path every time. To use a default instead:

```sh
mkdir -p ~/.config/vesktop-netns
mv ~/Downloads/your-file.conf ~/.config/vesktop-netns/wg.conf
chmod 600 ~/.config/vesktop-netns/wg.conf
```

Then run:

```sh
./vesktop-bypass.sh
```

Without an argument, the script looks for a config in this order:

1. `$VESKTOP_WG_CONF`
2. `~/.config/vesktop-netns/wg.conf`
3. `wg.conf` next to the script

## 4. Check the tunnel

Run this command to print the public IP address the tunnel uses, without starting Vesktop:

```sh
./vesktop-bypass.sh --test
```

The IP address must differ from your normal one. Compare it with the output of `curl ifconfig.me` outside the tunnel.

## Usage

```text
vesktop-bypass.sh [options] [WG_CONF] [-- VESKTOP_ARGS...]

  -t, --test      Print the tunnel's public IP and exit.
  -c, --cleanup   Remove leftover namespaces after a crash.
  -h, --help      Show help.
```

| Variable | Purpose |
| --- | --- |
| `VESKTOP_WG_CONF` | Default config path. |
| `VESKTOP_CMD` | Command that starts Vesktop. |
| `VESKTOP_DNS` | DNS servers (comma-separated). Overrides the config. |

Pass extra Vesktop flags after `--`:

```sh
./vesktop-bypass.sh -- --ozone-platform=x11
```

Optional: install a shortcut.

```sh
sudo install -m 755 vesktop-bypass.sh /usr/local/bin/vesktop-bypass
```

## How it works

1. `ip netns add` creates an empty namespace.
2. A WireGuard interface is created on the host, so its encrypted UDP packets can reach the server. The script then moves the interface into the namespace.
3. The script assigns the address, sets the default route to the tunnel, and writes a private `resolv.conf` for DNS. Only processes in the namespace see it.
4. `setpriv` drops root and starts Vesktop as your user. The script forwards the display, D-Bus, and audio environment variables (Wayland, X11, PipeWire, PulseAudio).
5. On exit, `Ctrl-C`, or an error, the script kills leftover processes and deletes the namespace, interface, and DNS files.

Security notes:

- Vesktop never runs as root. `sudo` is used only for network setup.
- The private key goes through a pipe to `wg setconf`. The script never writes it to a temporary file.
- The script ignores `PreUp`, `PostUp`, and similar hooks in the config file.
- The script validates addresses and DNS values before it passes them to privileged commands.
- IPv6 has no route unless the config has an IPv6 `Address`.
- `.gitignore` blocks all `*.conf` files except `wg.conf.example`.

## Troubleshooting

| Problem | Fix |
| --- | --- |
| `Vesktop is already running outside the tunnel` | Quit Vesktop fully, including the tray icon, then run the script again. A second launch would hand off to the existing window and bypass the tunnel. |
| No internet in Vesktop | Run `--test`. If it fails, the server or keys are wrong, or UDP is blocked. Try another server. |
| Name resolution fails | Set `VESKTOP_DNS=1.1.1.1`. |
| Connection stalls on large transfers | Add `MTU = 1280` to `[Interface]` in your config. |
| Leftover namespaces after a crash | Run `./vesktop-bypass.sh --cleanup`. |
| No window or audio | Run the script from your graphical session as your normal user, not from a different login or over SSH. |
| Flatpak Vesktop fails to start | Set `VESKTOP_CMD` to a native install, or check `flatpak run dev.vencord.Vesktop` outside the script. |

## Limitations

- Linux only.
- Applications that use abstract Unix sockets for X11 do not reach the X server from another namespace. Wayland and Xwayland (filesystem socket) work.
- Voice and video over WireGuard can be slower than your direct connection. Pick a nearby server.
- Only Vesktop is routed. Other Discord clients are not affected.

## License

MIT. See [LICENSE](LICENSE).
