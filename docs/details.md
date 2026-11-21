# Details

## Contents

- [Get a free WireGuard config](#get-a-free-wireguard-config)
- [Install dependencies manually](#install-dependencies-manually)
- [Config lookup order](#config-lookup-order)
- [Options and variables](#options-and-variables)
- [Lower call latency with `--split-voice`](#lower-call-latency-with---split-voice)
- [How it works](#how-it-works)
- [Security notes](#security-notes)
- [Troubleshooting](#troubleshooting)
- [Limitations](#limitations)

## Get a free WireGuard config

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

Any provider that exports a standard WireGuard config also works (Mullvad, IVPN, your own server). See [`wg.conf.example`](../wg.conf.example) for the format.

Never commit a real config. `.gitignore` blocks every `*.conf` file except `wg.conf.example`.

## Install dependencies manually

`make deps` covers these packages. To install them yourself, you need `iproute2`, `wireguard-tools`, `sudo`, `util-linux` (`setpriv`), `curl` (for `--test`), `zenity` or `kdialog` (launcher password dialog), and `nftables` plus `procps` (for `--split-voice`).

| Distro | Command |
| --- | --- |
| Arch, Manjaro, EndeavourOS | `sudo pacman -S wireguard-tools iproute2 sudo util-linux curl nftables procps-ng` |
| Debian, Ubuntu, Linux Mint | `sudo apt install wireguard-tools iproute2 sudo util-linux curl nftables procps` |
| Fedora | `sudo dnf install wireguard-tools iproute sudo util-linux curl nftables procps-ng` |
| openSUSE | `sudo zypper install wireguard-tools iproute2 sudo util-linux curl nftables procps` |

Your kernel needs WireGuard support (kernel 5.6 and later include it).

The script finds `vesktop` in your `PATH` first, then the Flatpak `dev.vencord.Vesktop`. To use another command, set `VESKTOP_CMD`.

## Config lookup order

Without a path argument, the script uses the first file that exists:

1. `$VESKTOP_WG_CONF`
2. `~/.config/vesktop-netns/wg.conf` (the file `make install` creates)
3. `wg.conf` next to the script

To switch configs, run `make install CONF=other.conf` again, or pass a path: `./vesktop-bypass.sh other.conf`.

## Options and variables

```text
vesktop-bypass.sh [options] [WG_CONF] [-- VESKTOP_ARGS...]

  -t, --test         Print the tunnel's public IP and exit.
  -s, --split-voice  Send voice/video UDP directly (lower call latency).
  -c, --cleanup      Remove leftover namespaces after a crash.
  -h, --help         Show help.
```

| Variable | Purpose |
| --- | --- |
| `VESKTOP_WG_CONF` | Default config path. |
| `VESKTOP_CMD` | Command that starts Vesktop. |
| `VESKTOP_DNS` | DNS servers (comma-separated). Overrides the config. |
| `VESKTOP_DIRECT_UDP_PORTS` | UDP ports sent directly in split mode. Default: `3478-3481,50000-65535`. |

Pass extra Vesktop flags after `--`:

```sh
./vesktop-bypass.sh -- --ozone-platform=x11
```

With make, use `ARGS`: `make run ARGS="--split-voice"`.

## Lower call latency with `--split-voice`

By default, voice goes through the VPN, which adds the round-trip time to the VPN server. With `--split-voice` (or `make split`), the script sends only voice and video UDP traffic over your normal connection. Login, chat, DNS, and all TCP traffic still use the tunnel.

Trade-offs:

- Discord voice servers see your real IP address.
- The script adds a temporary `nft` NAT rule on the host, limited to the namespace's veth interface. It removes the rule on exit.
- Firewalls that block forwarding (for example Docker's default `FORWARD` policy) can stop voice from connecting.
- Discord picks the voice region from the IP it sees on login. Set the channel's **Region Override** to a server near you.

Without split mode, pick the nearest free VPN server and set the region override to match it.

## How it works

1. `ip netns add` creates an empty namespace.
2. A WireGuard interface is created on the host, so its encrypted UDP packets can reach the server. The script then moves the interface into the namespace.
3. The script assigns the address, sets the default route to the tunnel, and writes a private `resolv.conf` for DNS. Only processes in the namespace see it.
4. The script waits for the WireGuard handshake and stops if it does not complete.
5. `setpriv` drops root and starts Vesktop as your user. The script forwards the display, D-Bus, and audio environment variables (Wayland, X11, PipeWire, PulseAudio).
6. On exit, `Ctrl-C`, or an error, the script kills leftover processes and deletes the namespace, interfaces, NAT rules, and DNS files.

In split mode, a veth pair links the namespace to the host. Inside the namespace, `nft` marks UDP packets for the direct ports, and a policy routing rule sends marked packets over the veth. The host masquerades them.

## Security notes

- The script asks for your password once and re-runs itself as root for the network setup. It then starts Vesktop with `setpriv` as your normal user, so Vesktop never runs as root.
- Because root runs the script file, keep it writable only by you. Anyone who can edit `~/.local/bin/vesktop-bypass` can run code as root the next time you enter your password. For shared machines, install it system-wide: `sudo install -m 755 vesktop-bypass.sh /usr/local/bin/vesktop-bypass`.
- The private key goes to `wg setconf` through stdin. The script never saves it to a file of its own.
- `make install` stores the config with mode `600` in a `700` directory.
- The script ignores `PreUp`, `PostUp`, and similar hooks in the config file.
- The script validates addresses, DNS values, and port lists before it passes them to privileged commands.
- IPv6 has no route unless the config has an IPv6 `Address`.

## Troubleshooting

| Problem | Fix |
| --- | --- |
| `Unknown device type` | The running kernel has no WireGuard module, usually after a kernel update. Reboot. |
| `Vesktop is already running outside the tunnel` | Quit Vesktop fully, including the tray icon, then run again. A second launch would hand off to the existing window and bypass the tunnel. |
| No WireGuard handshake | The config is expired or revoked, or your network blocks outgoing UDP. Download a config for another server. |
| Name resolution fails | Set `VESKTOP_DNS=1.1.1.1`. |
| Connection stalls on large transfers | Add `MTU = 1280` to `[Interface]` in your config. |
| Leftover namespaces after a crash | Run `./vesktop-bypass.sh --cleanup`. |
| No window or audio | Run from your graphical session as your normal user, not from SSH or another login. |
| Launcher entry does nothing | Check `~/.local/state/vesktop-netns/last.log`. The entry needs `zenity` or `kdialog` for the password dialog. |
| Flatpak Vesktop fails to start | Check `flatpak run dev.vencord.Vesktop` outside the script, or set `VESKTOP_CMD` to a native install. |
| `make install` says no config found | Run `make install CONF=path/to/your-file.conf`. |

## Limitations

- Linux only.
- Applications that use abstract Unix sockets for X11 cannot reach the X server from another namespace. Wayland and Xwayland (filesystem socket) work.
- Voice and video over a free VPN server can be slower than your direct connection.
- Only Vesktop is routed. Other Discord clients are not affected.
