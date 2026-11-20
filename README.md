<div align="center">

# Nexus Terminal

**A fast, local-first, open-source SSH & terminal client for every platform.**

Built with Flutter. No subscription. No mandatory cloud. No vendor lock-in.

![status](https://img.shields.io/badge/status-early%20development-orange)
![platform](https://img.shields.io/badge/platform-macOS%20%7C%20Windows%20%7C%20Linux%20%7C%20mobile%20%7C%20web-blue)
![license](https://img.shields.io/badge/license-MIT-green)

</div>

---

## Why Nexus Terminal?

Most polished SSH clients hide essential features behind a subscription, store your
connection data on their servers, and lock you into their ecosystem. Nexus Terminal
is built on the opposite principles:

| Common pain point | Nexus Terminal's answer |
| --- | --- |
| Core features behind a paywall | **Everything is free & open-source** |
| Connection data lives in a vendor cloud | **Local-first** — your data stays on your device |
| Expensive recurring subscription | **Free**, forever |
| Heavyweight (often Electron-based) | **Native-compiled** (Flutter) — small & fast |
| Hard to migrate away | Human-readable config, standard formats, no lock-in |
| Sync forces you onto their servers | *(planned)* **bring-your-own** end-to-end encrypted sync |

## Features

- 🖥️ **Local terminal** — runs your real shell (zsh/bash/cmd) with full ANSI color
- 🔌 **SSH client** — connect to any server (pure-Dart SSH, no external binaries)
- 🗂️ **Tabbed workspace** — many local & SSH sessions at once
- 💾 **Saved hosts** — one-click connect from a sidebar, no retyping
- 🔐 **Secrets in the OS keychain** — passwords & keys never stored as plain text
- 🔑 **Password & SSH-key auth**
- 📄 **Transparent storage** — host metadata as plain JSON you can back up or export

### Roadmap

- [x] Local terminal
- [x] SSH connections + tabbed workspace
- [x] Saved hosts + secure (keychain) secret storage
- [ ] SFTP file manager (drag & drop)
- [ ] Snippets & port forwarding
- [ ] Import from `~/.ssh/config`
- [ ] Optional end-to-end encrypted sync (Git / WebDAV / S3 — bring your own)
- [ ] Mobile (Android / iOS) & web builds

## Tech stack

- **[Flutter](https://flutter.dev/) / Dart** — single codebase, native performance
- **[xterm](https://pub.dev/packages/xterm)** — terminal emulation
- **[dartssh2](https://pub.dev/packages/dartssh2)** — pure-Dart SSH & SFTP
- **[flutter_pty](https://pub.dev/packages/flutter_pty)** — local shell (PTY)
- **[flutter_riverpod](https://pub.dev/packages/flutter_riverpod)** — state management
- **[flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage)** — OS keychain

## Getting started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable channel)
- Platform toolchain for your target (e.g. Xcode + CocoaPods for macOS)

### Run

```bash
git clone <your-repo-url>
cd nexus-terminal
flutter pub get
flutter run -d macos   # or: windows | linux | chrome
```

> **macOS note:** the app runs un-sandboxed so it can spawn shells and open
> network connections — standard for terminal apps. Re-enable the sandbox with
> appropriate entitlements if you target the Mac App Store.

## Project structure

```
lib/
├── main.dart                        # entry point
└── src/
    ├── app.dart                     # root app & theme
    ├── theme/                       # colors
    ├── models/                      # SshHost, SshCredentials
    ├── session/                     # TerminalSession abstraction
    ├── data/                        # host repository (JSON + keychain) + providers
    └── features/
        ├── terminal/                # local session + terminal view
        ├── ssh/                     # ssh session + connection form
        ├── hosts/                   # host editor + saved-hosts sidebar
        └── workspace/               # tabbed workspace screen
```

## Security

- Secrets (passwords, private keys, passphrases) are stored in the **operating
  system keychain**, never in the plain-text config.
- Host metadata (label, host, port, username) is stored as plain JSON in the app
  support directory — easy to inspect, back up, and export.
- Nothing is sent to any server you did not explicitly connect to.

## Contributing

This project is in early, active development — issues and pull requests are
welcome. Please open an issue to discuss significant changes before starting.

## License

[MIT](LICENSE) — free to use, modify, and distribute.
