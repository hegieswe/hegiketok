import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/ssh_credentials.dart';
import '../../ssh/ssh_connector.dart';
import '../../ssh/ssh_keys.dart';
import '../../theme/app_theme.dart';

/// Kartu yang menampilkan public key sebuah host: sidik jari, baris
/// `authorized_keys`, tombol salin, dan tombol pasang ke server.
class PublicKeyPanel extends StatefulWidget {
  const PublicKeyPanel({super.key, required this.info, this.onInstall});

  final SshPublicKeyInfo info;

  /// null = tombol "Pasang ke server" disembunyikan.
  final VoidCallback? onInstall;

  @override
  State<PublicKeyPanel> createState() => _PublicKeyPanelState();
}

class _PublicKeyPanelState extends State<PublicKeyPanel> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.info.line));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceInput,
        borderRadius: BorderRadius.circular(AppTheme.rSm),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.key_rounded, size: 14, color: AppTheme.accent),
              const SizedBox(width: 7),
              Text('Public key',
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: AppTheme.accentSoft,
                  borderRadius: BorderRadius.circular(AppTheme.rPill),
                ),
                child: Text(info.type,
                    style: TextStyle(
                        color: AppTheme.accent,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 7),
          SelectableText(
            info.fingerprint,
            maxLines: 1,
            style: TextStyle(
                color: AppTheme.textMuted, fontSize: 11, fontFamily: 'Menlo'),
          ),
          const SizedBox(height: 5),
          Text(
            info.line,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: AppTheme.textFaint, fontSize: 10.5, fontFamily: 'Menlo'),
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              OutlinedButton.icon(
                onPressed: _copy,
                style: _btnStyle(),
                icon: Icon(
                    _copied ? Icons.check_rounded : Icons.copy_rounded,
                    size: 14),
                label: Text(_copied ? 'Tersalin' : 'Salin public key'),
              ),
              if (widget.onInstall != null)
                OutlinedButton.icon(
                  onPressed: widget.onInstall,
                  style: _btnStyle(),
                  icon: const Icon(Icons.upload_rounded, size: 14),
                  label: const Text('Pasang ke server…'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  ButtonStyle _btnStyle() => OutlinedButton.styleFrom(
        foregroundColor: AppTheme.textPrimary,
        side: BorderSide(color: AppTheme.borderStrong),
        visualDensity: VisualDensity.compact,
        textStyle: const TextStyle(fontSize: 12),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      );
}

/// Dialog "pasang public key ke server" (setara `ssh-copy-id`): login sekali
/// dengan password, lalu menambahkan [publicKeyLine] ke `authorized_keys`.
/// Password hanya dipakai untuk koneksi ini dan tidak disimpan.
///
/// Mengembalikan true bila key terpasang (atau memang sudah ada).
Future<bool?> showInstallKeyDialog(
  BuildContext context, {
  required String host,
  required int port,
  required String username,
  required String publicKeyLine,
  required Future<List<SshCredentials>> Function() resolveJumpChain,
  String? initialPassword,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _InstallKeyDialog(
      host: host,
      port: port,
      username: username,
      publicKeyLine: publicKeyLine,
      resolveJumpChain: resolveJumpChain,
      initialPassword: initialPassword,
    ),
  );
}

enum _InstallPhase { input, working, done, failed }

class _InstallKeyDialog extends StatefulWidget {
  const _InstallKeyDialog({
    required this.host,
    required this.port,
    required this.username,
    required this.publicKeyLine,
    required this.resolveJumpChain,
    this.initialPassword,
  });

  final String host;
  final int port;
  final String username;
  final String publicKeyLine;
  final Future<List<SshCredentials>> Function() resolveJumpChain;
  final String? initialPassword;

  @override
  State<_InstallKeyDialog> createState() => _InstallKeyDialogState();
}

class _InstallKeyDialogState extends State<_InstallKeyDialog> {
  late final TextEditingController _password;
  _InstallPhase _phase = _InstallPhase.input;
  KeyInstallOutcome? _outcome;
  String? _error;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _password = TextEditingController(text: widget.initialPassword ?? '');
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_password.text.isEmpty) {
      setState(() => _error = 'Isi password server dulu.');
      return;
    }
    setState(() {
      _phase = _InstallPhase.working;
      _error = null;
    });
    SshConnection? conn;
    try {
      final jumps = await widget.resolveJumpChain();
      conn = await connectSsh(SshCredentials(
        host: widget.host,
        port: widget.port,
        username: widget.username,
        password: _password.text,
        jumpHosts: jumps,
      ));
      final outcome = await installPublicKey(conn.client, widget.publicKeyLine);
      if (!mounted) return;
      setState(() {
        _phase = _InstallPhase.done;
        _outcome = outcome;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _InstallPhase.failed;
        _error = _friendlyInstallError(e);
      });
    } finally {
      conn?.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final working = _phase == _InstallPhase.working;
    final done = _phase == _InstallPhase.done;
    final target = '${widget.username}@${widget.host}:${widget.port}';

    return AlertDialog(
      backgroundColor: AppTheme.surface,
      title: Row(
        children: [
          Icon(Icons.upload_rounded, size: 18, color: AppTheme.accent),
          const SizedBox(width: 9),
          Text('Pasang key ke server',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5),
                children: [
                  const TextSpan(
                      text: 'Public key akan ditambahkan ke '
                          '~/.ssh/authorized_keys milik '),
                  TextSpan(
                    text: target,
                    style: TextStyle(
                        color: AppTheme.textPrimary, fontFamily: 'Menlo'),
                  ),
                  const TextSpan(
                      text: '. Setelah itu host ini bisa login tanpa '
                          'password.'),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (!done) ...[
              Text('Password server (dipakai sekali, tidak disimpan)',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
              const SizedBox(height: 6),
              TextField(
                controller: _password,
                enabled: !working,
                autofocus: true,
                obscureText: _obscure,
                onSubmitted: (_) => working ? null : _run(),
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: AppTheme.surfaceInput,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                      color: AppTheme.textMuted,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.rSm),
                    borderSide: BorderSide(color: AppTheme.border),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.rSm),
                    borderSide: BorderSide(color: AppTheme.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.rSm),
                    borderSide: BorderSide(color: AppTheme.accent),
                  ),
                ),
              ),
            ],
            if (working) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppTheme.accent),
                  ),
                  const SizedBox(width: 10),
                  Text('Menghubungkan & memasang key…',
                      style:
                          TextStyle(color: AppTheme.textMuted, fontSize: 12.5)),
                ],
              ),
            ],
            if (done)
              _note(
                Icons.check_circle_rounded,
                AppTheme.success,
                _outcome == KeyInstallOutcome.alreadyPresent
                    ? 'Key ini sudah terdaftar di server — tidak ada yang '
                        'diubah.'
                    : 'Key terpasang. Simpan host ini, lalu koneksi berikutnya '
                        'memakai key.',
              ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _note(Icons.error_outline_rounded, AppTheme.danger, _error!),
            ],
          ],
        ),
      ),
      actions: [
        if (!done)
          TextButton(
            onPressed: working ? null : () => Navigator.of(context).pop(false),
            child: Text('Batal', style: TextStyle(color: AppTheme.textMuted)),
          ),
        if (done)
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: AppTheme.onAccent),
            child: const Text('Selesai'),
          )
        else
          FilledButton(
            onPressed: working ? null : _run,
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: AppTheme.onAccent),
            child: Text(
                _phase == _InstallPhase.failed ? 'Coba lagi' : 'Pasang key'),
          ),
      ],
    );
  }

  Widget _note(IconData icon, Color color, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: TextStyle(
                  color: color == AppTheme.danger
                      ? AppTheme.danger
                      : AppTheme.textPrimary,
                  fontSize: 12.5)),
        ),
      ],
    );
  }
}

String _friendlyInstallError(Object e) {
  if (e is KeyInstallException) return e.message;
  final t = e.toString().toLowerCase();
  if (t.contains('auth')) {
    return 'Login ditolak — password salah, atau server tidak mengizinkan '
        'login password.';
  }
  if (t.contains('refused')) return 'Koneksi ditolak — cek host & port.';
  if (t.contains('timed out') || t.contains('timeout')) {
    return 'Server tidak merespons (timeout).';
  }
  if (t.contains('failed host lookup')) return 'Host tidak ditemukan.';
  if (t.contains('host key')) return 'Host key ditolak.';
  return 'Gagal: $e';
}
