# BookFinder

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

## Limits and privacy


Use your own account. No passwords, session cookies or books are distributed. The current small-screen password input is visible; the password is used only for the login request, while the session stays in device app state. Do not share that state. Download quotas are controlled by the provider and are not bypassed.

Run the six offline regression scripts in `tests/` with `uv run --no-project --with lupa python tests/<script>.py`. These tests do not log in or download books.

MIT license; see [LICENSE](LICENSE) and [NOTICE](NOTICE.md). This is not an official Z-Library or Xteink app. Only access material you are entitled to use.
