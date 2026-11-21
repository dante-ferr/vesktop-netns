# vesktop-netns

Run [Vesktop](https://github.com/Vencord/Vesktop) through a WireGuard VPN. Only Vesktop uses the tunnel. The rest of your network stays unchanged. If the tunnel drops, Vesktop goes offline instead of leaking your real IP.

## Setup

1. Install [Vesktop](https://github.com/Vencord/Vesktop) (package manager, AUR, or `flatpak install flathub dev.vencord.Vesktop`).
2. Download a WireGuard `.conf` file. For a free one, see [Get a free config](docs/details.md#get-a-free-wireguard-config).
3. Clone the repository and install:

   ```sh
   git clone https://github.com/dante-ferr/vesktop-netns.git
   cd vesktop-netns
   make deps
   make install CONF=~/Downloads/your-file.conf
   ```

   - `make deps` installs the required packages for your distro.
   - `make install` saves your config to `~/.config/vesktop-netns/wg.conf` (mode `600`), installs the script to `~/.local/bin`, and adds **Vesktop Netns** to your app launcher.

4. Reboot if you recently updated your kernel. WireGuard needs the kernel's modules to match the running kernel.

## Use

Open **Vesktop Netns** from your app launcher. A dialog asks for your password, and no terminal opens. Output goes to `~/.local/state/vesktop-netns/last.log`. Or run in a terminal:

```sh
make run
```

Enter your password when `sudo` asks. Close Vesktop to remove the namespace and tunnel.

To check the tunnel first, run `make test`. It prints the public IP address the tunnel uses. The address must differ from the output of `curl ifconfig.me`.

## Commands

| Command | Action |
| --- | --- |
| `make deps` | Install dependencies for your distro. |
| `make install CONF=file.conf` | Save the config, install the script, and add the launcher entry. |
| `make run` | Run Vesktop through the tunnel. |
| `make split` | Run with direct voice and video traffic (lower call latency). |
| `make test` | Print the public IP seen through the tunnel. |
| `make uninstall` | Remove the script and launcher entry. Your saved config stays. |

You can also run `./vesktop-bypass.sh --help` directly.

## Problems

| Problem | Fix |
| --- | --- |
| `Unknown device type` or WireGuard unavailable | Reboot. Your running kernel no longer matches the installed modules. |
| `Vesktop is already running outside the tunnel` | Quit Vesktop fully, including the tray icon, then run again. |
| No handshake or no internet | The config is expired or UDP is blocked. Download a config for another server. |
| Calls lag | Try `make split`. See [Lower call latency](docs/details.md#lower-call-latency-with---split-voice). |
| Leftover namespaces after a crash | Run `./vesktop-bypass.sh --cleanup`. |

More solutions: [docs/details.md](docs/details.md#troubleshooting).

## Documentation

[docs/details.md](docs/details.md) covers free configs, all options and variables, split voice, how it works, security, and limitations.

## License

MIT. See [LICENSE](LICENSE).
