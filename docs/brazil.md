# Guide for users in Brazil

This guide explains how to get Discord screen sharing working from Brazil with the lowest latency. It assumes you finished the setup in the [README](../README.md).

## Contents

- [Recommended setup](#recommended-setup)
- [Choose a Proton server](#choose-a-proton-server)
- [Use split voice](#use-split-voice)
- [Set the voice region](#set-the-voice-region)
- [Check that it works](#check-that-it-works)
- [Troubleshooting](#troubleshooting)

## Recommended setup

1. Use a Proton VPN server in the United States. A free US server works well.
1. Open **Vesktop Netns (split voice)** from your app launcher.
1. Set the voice channel's **Region Override** to a US region.

This setup was tested with the free server `US-FREE#1`. Results depend on your ISP and the server load.

## Choose a Proton server

Every chat message, image, and API request goes through the VPN server. The distance to that server decides how fast Discord feels. A far server adds hundreds of milliseconds to everything.

Follow these steps:

1. Open the Proton dashboard and go to **Downloads** > **WireGuard configuration**.
1. Select **GNU/Linux**.
1. Select a server in the United States. Pick one with a low load.
1. Download the file and install it:

   ```sh
   make install CONF=~/Downloads/your-file.conf
   ```

1. Measure the latency to the server:

   ```sh
   ping -c 10 "$(grep -i '^Endpoint' ~/.config/vesktop-netns/wg.conf | sed 's/.*= *//; s/:.*//')"
   ```

Aim for a round trip under about 150 ms. If it is much higher, try another server. Servers in Europe or Asia often reach 250 ms or more from Brazil.

Avoid Secure Core servers. They route traffic through a second hop and add latency.

Free servers can be busy at peak hours. If latency changes during the day, try a different free server.

## Use split voice

By default, all traffic goes through the VPN, including voice and screen sharing. This adds the VPN round trip to your calls.

The **Vesktop Netns (split voice)** entry sends only voice and video UDP traffic over your normal connection. Login, chat, DNS, and all TCP traffic still use the VPN. Screen sharing keeps working because Discord checks the IP address on the main connection, and that connection stays in the tunnel.

The trade-off is privacy. Discord's voice servers see your real IP address. Use the normal **Vesktop Netns** entry if that matters to you. Details are in [Lower call latency](details.md#lower-call-latency-with---split-voice).

Split mode does not make chat faster. Chat uses the VPN in both modes, so only a closer server helps.

## Set the voice region

Discord picks the voice region from the IP address it sees. In split mode, that is not always the region you want.

1. Right-click the voice channel and select **Edit Channel**.
1. Open **Overview**.
1. Set **Region Override** to a region near your VPN server.

You need the permission to edit the channel. If you do not have it, ask a server admin to set it.

## Check that it works

Run the built-in test. It prints the public IP address seen through the tunnel:

```sh
./vesktop-bypass.sh --test
```

The address must not be a Brazilian address. If it is, the tunnel is not working.

## Troubleshooting

| Problem | Solution |
| --- | --- |
| Screen sharing is still blocked | Run `./vesktop-bypass.sh --test` and confirm the IP is outside Brazil. Try another server. |
| Everything is slow | Measure the server ping. Choose a closer server if it is above about 150 ms. |
| Chat is slow but calls are fine | Split mode only speeds up voice and video. Choose a closer server. |
| Voice does not connect in split mode | A firewall may block forwarding. See [Troubleshooting](details.md#troubleshooting). |
| `Unknown device type` | Reboot. Your running kernel no longer matches the installed modules. |
