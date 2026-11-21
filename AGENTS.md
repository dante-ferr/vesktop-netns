# AGENTS.md

Guidance for AI agents working in this repository.

## Project

`vesktop-netns` runs [Vesktop](https://github.com/Vencord/Vesktop) inside a Linux network namespace. All of its traffic goes through a WireGuard tunnel. The rest of the system's network stays unchanged. The goal is to let users in regions where Discord streaming is blocked (for example Brazil) stream anyway.

The project must stay lightweight, plug-and-play, and shareable across Linux distributions.

## Repository layout

| Path | Purpose |
| --- | --- |
| `vesktop-bypass.sh` | The main script. Single file, Bash. |
| `Makefile` | `deps`, `install`, `uninstall`, `run`, `split`, `test`. |
| `README.md` | Short, beginner-friendly setup and usage. |
| `docs/details.md` | Detailed documentation: configs, options, split voice, security, troubleshooting. |
| `wg.conf.example` | Placeholder WireGuard config. Never contains real keys. |
| `.gitignore` | Blocks every `*.conf` except `wg.conf.example`. |

## Architecture

- A namespace named `vesktop-<pid>` contains a loopback interface and one WireGuard interface. There is no other path out, so a dropped tunnel means no connectivity (kill switch).
- The WireGuard interface is created in the host namespace and then moved into the namespace. This keeps its UDP socket on the host so the tunnel can reach the server.
- DNS comes from `/etc/netns/<name>/resolv.conf`. The file must be world-readable (`644`) because Vesktop runs as the unprivileged user.
- The script waits for a WireGuard handshake and aborts if none occurs.
- Vesktop runs through `setpriv` as the invoking user. Display, D-Bus, and audio variables are forwarded explicitly (`FORWARD_VARS`).
- `--split-voice` (opt-in) sends voice/video UDP through a veth pair with host NAT. It is a documented privacy trade-off.
- A trap removes the namespace, interfaces, `nft` tables, and DNS files on every exit path. `--cleanup` removes leftovers from crashes.
- `make install` requires a WireGuard config (`CONF=...`). It saves the file to `~/.config/vesktop-netns/wg.conf` with mode `600` and installs a launcher entry (`Terminal=false`).

## Security rules

- Vesktop must never run as root.
- Never write the WireGuard private key to a file the script creates, and never print it.
- Never execute `PreUp`, `PostUp`, or similar hooks from the config. Use `wg-quick strip` only to remove them.
- Validate every value from the config or environment (addresses, DNS, MTU, ports) before it reaches a privileged command.
- Never commit a real `.conf` file, key, or token.
- Do not add network behavior that sends traffic outside the tunnel unless it is opt-in and documented.
- Do not modify global host networking (global `ip_forward`, existing firewall rules, default routes). Scope changes to objects the script creates, and remove them on exit.

## Coding standards

- Bash with `set -Eeuo pipefail`. The script must pass `bash -n` and, when available, `shellcheck`.
- Write code, comments, and documentation in clear English.
- Keep functions small and single-purpose. Quote all expansions.
- Support major distributions: Arch, Debian/Ubuntu, Fedora, openSUSE. Do not rely on distro-specific paths or tools without a check.
- Keep dependencies minimal. Add a new one only when needed, and add it to `make deps`, the README, and `docs/details.md`.
- Keep the README short. Put detail in `docs/details.md`.

## Documentation style

Follow the [Google developer documentation style guide](https://developers.google.com/style):

- Use active voice and second person.
- Write short sentences. Lead with the action.
- Use sentence-case headings, serial commas, and American spelling.
- Put code, commands, and file names in backticks.
- Do not use filler, slang, or exclamation marks.

## Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org/): `<type>[optional scope]: <description>`, with an optional body and footers. Use `feat`, `fix`, `docs`, `refactor`, `chore`, and similar types. Mark breaking changes with `!` or a `BREAKING CHANGE:` footer.

## Testing notes

- The script needs root for network setup. Agents often cannot enter a sudo password, so test syntax with `bash -n` and exercise argument parsing with `--help`. Ask the user to run end-to-end checks.
- `./vesktop-bypass.sh --test` verifies the tunnel and prints the public IP.
- A kernel update without a reboot makes `ip link add ... type wireguard` fail with `Unknown device type`. This is a host issue, not a script bug.
- Wayland and PipeWire sockets are filesystem sockets and work inside the namespace. Abstract X11 sockets do not.
