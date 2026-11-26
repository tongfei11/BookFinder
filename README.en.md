# BookFinder

A third-party **Z-Library client for the Xteink X4 Pro**. Discover a server, log in with your own Z-Library account, search books, view details, download EPUB/TXT files, and open them in the system reader. The e-ink interface supports touch and hardware keys. Current XTApp build: **0031**.

This is not an official Z-Library app. It does not provide book files or shared accounts.

[中文](README.md)


## Features

- Website search, book details and explicit download actions, EPUB/TXT format selection.
- Server discovery, account sessions retained when switching servers, live account quota.
- Download waiting time, downloaded-file list, open and delete.
- E-ink friendly black-and-white lists, hardware-key/swipe detail paging, fixed action footer.
- Follows the system language: Chinese for `zh` and `zh-TW`, English fallback for all others. Book titles, authors and descriptions remain in their original language.

## Download and install

Download **BookFinder-0031.xtapp** from [Releases](https://github.com/tongfei11/BookFinder/releases). Put the reader into USB mode, copy it to the SD card, safely eject, then tap the package in the reader's file manager to install.

Requires Gancao firmware. Reader opening was verified on X4 Pro firmware 26112101. English physical-device layout testing is pending. The package is built and self-checked by Studio's encrypted packager. Source code is in `xtapp/`.

## First use

1. Tap **Check server** at the bottom of the home screen to try the built-in original-domain candidates. If unavailable, tap **Check mirror** to refresh and check addresses from the directory below. The selected address appears on the home screen; server detection is required before login or search.
2. Tap **Log in** at the top right and enter your own Z-Library email and password. After login, the button becomes **Account**, and the home screen shows your download quota. Switching server addresses retains your login information.
3. Enter a title, author or ISBN on the home screen and tap **Search**. Website search returns EPUB/TXT entries with title, author and size. Use page buttons or hardware keys to browse the list.
4. Tap **View** to see the full title, author, size and description, then tap **Download** at the bottom. Choose a format if multiple formats are available. Hardware keys or vertical swipes page through details.
5. Open **Downloads** from the home screen to open a file in the system reader or delete it with confirmation.

## Server and mirror sources

| Home button | Source and behavior |
| --- | --- |
| Check server | Tries built-in original-domain candidates, including `https://z-lib.gd`. See the full list in [xtapp/mirrors.lua](xtapp/mirrors.lua). This is not a live official address announcement. |
| Check mirror | Reads the README of [dongyubin/Awesome-Zlibrary](https://github.com/dongyubin/Awesome-Zlibrary) at runtime, extracts entries marked accessible in its mainland-China availability table, replaces the cached candidate list and checks it. A failed refresh preserves the previous list. |

The mirror directory is maintained by a third party. Its availability labels do not guarantee access on your network or imply official Z-Library endorsement. The home screen shows the server actually selected. A successful server check only verifies the detection endpoint; login, search or download may still be restricted upstream.

The app uses the reader's current Wi-Fi connection and has no built-in HTTP/SOCKS5 proxy. For `Access denied` or connection failures, try the other server group. If both fail, check whether searching the same address works in a browser; download there and transfer the file to the reader if necessary.

Protocol research references [heartleo/zlib](https://github.com/heartleo/zlib); this client is independently implemented in Lua. See [NOTICE](NOTICE.md) for attribution and licensing.

## Limits and privacy

Direct downloads are limited to **8 MiB** by the current firmware. Larger files trigger a message when Download is tapped; download them in a browser and transfer them instead. Download status shows elapsed waiting time, not a simulated percentage. Upstream website or verification changes may interrupt service.

Use your own account. No passwords, session cookies or books are distributed. The current small-screen password input is visible; the password is used only for the login request, while the session stays in device app state. Do not share that state. Download quotas are controlled by the provider and are not bypassed.

Run the six offline regression scripts in `tests/` with `uv run --no-project --with lupa python tests/<script>.py`. These tests do not log in or download books.

MIT license; see [LICENSE](LICENSE) and [NOTICE](NOTICE.md). This is not an official Z-Library or Xteink app. Only access material you are entitled to use.
