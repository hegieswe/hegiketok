<div align="center">

# HegiKetok

**A local-first, open-source SSH & terminal client for the desktop.**

Built with Flutter. No subscription. No account. No mandatory cloud.

![status](https://img.shields.io/badge/status-active%20development-orange)
![platform](https://img.shields.io/badge/platform-macOS-blue)
![license](https://img.shields.io/badge/license-MIT-green)

<sub>The name blends the maker's name <i>Hegi</i> with the Sundanese word <i>ketok</i> ("to knock"), as in knocking on a server's door to be let in.</sub>

</div>

---

## Why HegiKetok?

Many polished SSH clients put essential features behind a subscription, keep
your connection data on their servers, and make it hard to leave. HegiKetok
takes the opposite approach:

| Common pain point | HegiKetok's answer |
| --- | --- |
| Core features behind a paywall | Everything is free and open-source |
| Connection data lives in a vendor cloud | Data stays on your device |
| Heavyweight Electron shell | Native-compiled Flutter app |
| Hard to migrate away | Plain JSON metadata, standard key formats, encrypted export |

## Features

### Terminal and sessions

- **Local terminal** running your real shell, with nine built-in color themes
  and adjustable font size.
- **Tabbed workspace** for local shells, SSH sessions, and server panels.
- **Split panes**, side by side or stacked, with a draggable divider and
  **synchronized input** to type into both panes at once.
- **Search in scrollback** (`⌘F`) and a **command palette** (`⌘K`).
- **Snippets**: saved commands you can run in the active session.

### SSH

- **Saved hosts** with tags, search, and a per-host OS icon.
- **Connection test** in the host editor, plus warnings for usernames and
  addresses that look mistyped, so mistakes surface before you save.
- **Actionable connection errors**: a failed login names the username that was
  used and offers "Edit host" and "Retry"; a server that is temporarily
  blocking you after repeated failures is reported as such, not as a wrong
  password.
- **Password and key authentication**, with secrets stored in the OS keychain.
- **SSH key management**: generate an ed25519 key pair in the host editor,
  view and copy its public key and fingerprint, and install it on the server
  (the equivalent of `ssh-copy-id`).
- **Agent forwarding**, opt-in per host and applied to the target host only.
- **Jump hosts** (bastions), including multi-hop chains.
- **Host key verification** on first use, with a manageable known-hosts list.
- **Local port forwarding.**
- **Import from `~/.ssh/config`.**
- **Live connection status**: a host shows as online only while its session is
  actually connected.

### tmux

- **Persistent sessions**: per host, wrap the shell in
  `tmux new-session -A` so programs keep running through disconnects and a
  reconnect resumes the same session. Falls back to a plain shell when tmux is
  not installed.
- **Control mode** (`tmux -CC`, experimental): tmux windows appear as tabs and
  panes as native splits, with resize and existing pane content on attach.

### Server panels

Opened per host over the same SSH connection:

- **SFTP** dual-pane file manager (local and remote).
- **Server info** dashboard with CPU, memory, and disk alerts.
- **Docker** containers, **systemd services**, **cron** jobs, and **users**.

### Data and updates

- **Encrypted backup and restore** of hosts, snippets, and known hosts
  (AES-256-GCM, key derived from your password).
- **Automatic host-list history**: every change keeps the previous version
  (the last 15), restorable from Settings. Secrets stay in the keychain.
- **Update check** against this repository's GitHub Releases, with in-app
  download and checksum verification.
- **Light, dark, and system themes.**

## Platform support

| Platform | Status |
| --- | --- |
| macOS 12+ | Developed and tested here |
| Linux, Windows | Built by CI, not yet tested |
| Android, iOS | Project scaffolding only, never built |

## Install

Prebuilt macOS packages are attached to
[Releases](https://github.com/hegieswe/hegiketok/releases) once a version has
been published. Until then, build from source as described below.

Release builds are ad-hoc signed, not notarized. On a Mac other than the one
that built the app, macOS blocks the first launch; allow it once under
**System Settings → Privacy & Security → Open Anyway**. See
[DISTRIBUTION.md](DISTRIBUTION.md) (in Indonesian) for details.

## Build from source

Requirements: the [Flutter SDK](https://docs.flutter.dev/get-started/install)
(stable channel) and, for macOS, Xcode with CocoaPods.

```bash
git clone https://github.com/hegieswe/hegiketok.git
cd hegiketok
flutter pub get
flutter run -d macos
```

To produce a signed `.dmg` and `.zip` in `dist/`:

```bash
./scripts/release_macos.sh
```

> If you rebuild while the app is open, quit and relaunch it. macOS treats a
> running app whose bundle was re-signed as invalid, and the keychain then
> refuses to store secrets.

## Tests

```bash
flutter analyze
flutter test
```

Most tests are self-contained, including widget tests that drive the host
editor and dialogs. The integration tests (SSH, SFTP, key install,
agent forwarding, tmux) expect an OpenSSH server on `127.0.0.1:2222` with user
`nexus` and password `nexus123`, and tmux installed for the tmux tests. When
that server is not running they are reported as skipped. These are throwaway
credentials for a local test container only.

## Security and privacy

- Passwords, private keys, and passphrases are stored in the **OS keychain**,
  never in plain-text files.
- Host metadata (label, address, port, username, tags) is stored as plain JSON
  in the app support directory, so it is easy to inspect and back up.
- Keys generated in the app are stored unencrypted inside the keychain, which
  is what protects them.
- The app runs without the macOS App Sandbox, because a terminal must spawn
  shells. This also means it cannot be distributed through the Mac App Store.
- Network traffic is limited to the servers you connect to and the update
  check. The automatic check sends one public request to `api.github.com` at
  most once a day, carries no user data, and can be turned off in Settings.
- There is no telemetry and no account.

To report a vulnerability, please open a private security advisory on GitHub
rather than a public issue.

## Project structure

```
lib/
├── main.dart
└── src/
    ├── app.dart            # root widget and theme wiring
    ├── theme/              # palette, shared UI kit, brand mark
    ├── models/             # SshHost, SshCredentials
    ├── session/            # terminal session and workspace tab interfaces
    ├── data/               # host/snippet repositories, credentials, encrypted vault
    ├── ssh/                # connector, known hosts, key tools, tmux protocol
    └── features/
        ├── workspace/      # tabs, splits, title bar
        ├── hosts/          # host list, editor, key tools, ssh config import
        ├── terminal/       # local shell and terminal view
        ├── ssh/            # SSH sessions, port forwarding, tmux control mode
        ├── sftp/           # dual-pane file manager
        ├── server_info/ docker/ services/ cron/ users/
        ├── snippets/ command_palette/
        ├── settings/       # themes, backup, known hosts
        └── updates/        # GitHub Releases updater
```

## Tech stack

- [Flutter](https://flutter.dev/) and Dart
- [xterm](https://pub.dev/packages/xterm) for terminal emulation
- [dartssh2](https://pub.dev/packages/dartssh2) for SSH and SFTP in pure Dart
- [flutter_pty](https://pub.dev/packages/flutter_pty) for the local shell
- [flutter_riverpod](https://pub.dev/packages/flutter_riverpod) for state
- [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage) for the OS keychain
- [pointycastle](https://pub.dev/packages/pointycastle) and
  [pinenacl](https://pub.dev/packages/pinenacl) for backup encryption and
  ed25519 keys

The interface is currently in Indonesian.

## Roadmap

- Run one command across a group of hosts
- Session recording to a file
- Dynamic (SOCKS) and remote port forwarding
- Optional sync through a folder or Git repository you control
- English interface
- Tested Linux and Windows releases

## Contributing

Issues and pull requests are welcome. For larger changes, please open an issue
first to discuss the approach. Run `flutter analyze` and `flutter test` before
submitting; the project is kept free of analyzer warnings.

## License

[MIT](LICENSE)
