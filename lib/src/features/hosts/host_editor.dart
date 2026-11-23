import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import '../../data/host_credentials.dart';
import '../../data/host_providers.dart';
import '../../models/ssh_host.dart';
import '../../ssh/ssh_keys.dart';
import '../../theme/app_theme.dart';
import 'host_os.dart';
import 'key_tools.dart';

/// Tampilkan dialog tambah/edit host. [existing] diisi saat mengedit.
/// Mengembalikan true bila host disimpan.
Future<bool?> showHostEditor(BuildContext context, {SshHost? existing}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _HostEditorDialog(existing: existing),
  );
}

class _HostEditorDialog extends ConsumerStatefulWidget {
  const _HostEditorDialog({this.existing});

  final SshHost? existing;

  @override
  ConsumerState<_HostEditorDialog> createState() => _HostEditorDialogState();
}

class _HostEditorDialogState extends ConsumerState<_HostEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _label;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _user;
  final _password = TextEditingController();
  final _keyPath = TextEditingController();
  final _passphrase = TextEditingController();
  final _tagInput = TextEditingController();
  late final TextEditingController _startup;

  final List<String> _tags = [];
  SshAuthMethod _method = SshAuthMethod.password;
  HostOs _os = HostOs.auto;
  String? _jumpHostId;
  bool _persistent = false;
  bool _forwardAgent = false;
  bool _obscure = true;

  // Konten private key yang sudah dimuat dari file / baru dibuat (jika ada).
  String? _loadedKey;

  // Rahasia yang sudah tersimpan untuk host ini (saat mengedit).
  HostSecret? _stored;

  // true bila Keychain sudah terbaca (sehingga "tidak ada key" itu pasti).
  bool _secretKnown = false;

  // Public key dari key yang sedang aktif (baru dimuat, atau yang tersimpan).
  SshPublicKeyInfo? _publicKey;
  String? _publicKeyError;
  String? _keyStatus;
  String? _saveError;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  // ID host baru dibuat SEKALI per dialog, supaya menekan Simpan lagi setelah
  // gagal tidak menghasilkan host ganda.
  late final String _newHostId = const Uuid().v4();

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _label = TextEditingController(text: e?.label ?? '');
    _host = TextEditingController(text: e?.host ?? '');
    _port = TextEditingController(text: (e?.port ?? 22).toString());
    _user = TextEditingController(text: e?.username ?? '');
    _method = e?.authMethod ?? SshAuthMethod.password;
    _jumpHostId = e?.jumpHostId;
    _os = e?.os ?? HostOs.auto;
    _persistent = e?.persistentSession ?? false;
    _forwardAgent = e?.forwardAgent ?? false;
    _tags.addAll(e?.tags ?? const []);
    _startup = TextEditingController(text: e?.startupCommand ?? '');
    if (e != null) _loadStoredSecret(e.id);
  }

  Future<void> _loadStoredSecret(String id) async {
    try {
      final secret = await ref.read(hostRepositoryProvider).loadSecret(id);
      if (!mounted) return;
      setState(() {
        _stored = secret;
        _secretKnown = true;
      });
      _refreshPublicKey();
    } catch (_) {
      // Keychain tak terbaca → panel public key cukup tidak tampil.
    }
  }

  /// Private key yang berlaku sekarang: yang baru dimuat/dibuat, atau yang
  /// sudah tersimpan untuk host ini.
  String? get _activeKey => _loadedKey ?? _stored?.privateKey;

  String get _keyComment {
    final name = _label.text.trim().isNotEmpty ? _label.text : _host.text;
    final c = sanitizeKeyComment(name);
    return c.isEmpty ? 'hegiketok' : 'hegiketok@$c';
  }

  /// Hitung ulang public key dari [_activeKey] (dan passphrase yang relevan).
  void _refreshPublicKey() {
    final pem = _activeKey;
    if (pem == null || pem.trim().isEmpty) {
      setState(() {
        _publicKey = null;
        _publicKeyError = null;
      });
      return;
    }
    final typed = _passphrase.text;
    // Passphrase tersimpan hanya berlaku untuk key yang tersimpan.
    final pass = typed.isNotEmpty
        ? typed
        : (_loadedKey == null ? _stored?.passphrase : null);
    try {
      final info =
          describePrivateKey(pem, passphrase: pass, comment: _keyComment);
      setState(() {
        _publicKey = info;
        _publicKeyError = null;
      });
    } on SshKeyException catch (e) {
      setState(() {
        _publicKey = null;
        _publicKeyError = e.message;
      });
    }
  }

  Future<void> _generateKey() async {
    if (_activeKey != null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: Text('Ganti key host ini?',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
          content: SizedBox(
            width: 380,
            child: Text(
              'Key baru akan menggantikan key yang sekarang saat kamu menekan '
              'Simpan. Server baru menerima key baru setelah public key-nya '
              'dipasang — pakai "Pasang ke server…" sebelum menyimpan.',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child:
                  Text('Batal', style: TextStyle(color: AppTheme.textMuted)),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: AppTheme.onAccent),
              child: const Text('Buat key baru'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    final key = generateEd25519Key(comment: _keyComment);
    _keyPath.clear();
    _passphrase.clear();
    setState(() {
      _loadedKey = key.privatePem;
      _publicKey = key.public;
      _publicKeyError = null;
      _keyStatus = '✓ Key ed25519 baru dibuat — disimpan ke Keychain saat '
          'kamu menekan Simpan';
    });
  }

  Future<void> _installKey() async {
    final info = _publicKey;
    if (info == null) return;
    if (_host.text.trim().isEmpty || _user.text.trim().isEmpty) {
      setState(() =>
          _keyStatus = '✗ Isi Host dan Username dulu sebelum memasang key');
      return;
    }
    final repo = ref.read(hostRepositoryProvider);
    final all = ref.read(hostsProvider).asData?.value ?? const <SshHost>[];
    final installed = await showInstallKeyDialog(
      context,
      host: _host.text.trim(),
      port: int.tryParse(_port.text.trim()) ?? 22,
      username: _user.text.trim(),
      publicKeyLine: info.line,
      initialPassword: _password.text.isNotEmpty
          ? _password.text
          : _stored?.password,
      resolveJumpChain: () => resolveJumpChain(
        _jumpHostId,
        loadSecret: repo.loadSecret,
        allHosts: all,
        visited: {if (widget.existing != null) widget.existing!.id},
      ),
    );
    if (installed == true && mounted) {
      setState(() => _keyStatus = '✓ Public key terpasang di server');
    }
  }

  void _addTag(String raw) {
    final tag = raw.trim().toLowerCase();
    if (tag.isEmpty) return;
    if (!_tags.contains(tag)) setState(() => _tags.add(tag));
    _tagInput.clear();
  }

  @override
  void dispose() {
    _label.dispose();
    _host.dispose();
    _port.dispose();
    _user.dispose();
    _password.dispose();
    _keyPath.dispose();
    _passphrase.dispose();
    _tagInput.dispose();
    _startup.dispose();
    super.dispose();
  }

  Future<void> _loadKeyFile() async {
    final path = _keyPath.text.trim();
    if (path.isEmpty) return;
    try {
      final content = await File(path).readAsString();
      setState(() {
        _loadedKey = content;
        _keyStatus = '✓ Key dimuat (${content.length} karakter)';
      });
      _refreshPublicKey();
    } catch (e) {
      setState(() {
        _loadedKey = null;
        _keyStatus = '✗ Gagal membaca file: periksa path';
      });
      _refreshPublicKey();
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // Validasi khusus metode key saat membuat host baru.
    // Saat mengedit, hanya blokir bila Keychain sudah terbaca dan memang
    // kosong — jangan menghalangi simpan gara-gara Keychain lambat/terkunci.
    if (_method == SshAuthMethod.key &&
        _activeKey == null &&
        (!_isEdit || _secretKnown)) {
      setState(
          () => _keyStatus = '✗ Muat file private key atau buat key baru dulu');
      return;
    }

    setState(() {
      _saving = true;
      _saveError = null;
    });

    final host = (widget.existing ??
            SshHost(
              id: _newHostId,
              label: '',
              host: '',
              username: '',
            ))
        .copyWith(
      label: _label.text.trim().isEmpty ? _host.text.trim() : _label.text.trim(),
      host: _host.text.trim(),
      port: int.tryParse(_port.text.trim()) ?? 22,
      username: _user.text.trim(),
      authMethod: _method,
      jumpHostId: _jumpHostId,
      clearJumpHost: _jumpHostId == null,
      tags: List<String>.unmodifiable(_tags),
      startupCommand: _startup.text.trim(),
      os: _os,
      persistentSession: _persistent,
      forwardAgent: _method == SshAuthMethod.key && _forwardAgent,
    );

    final isPassword = _method == SshAuthMethod.password;
    try {
      await ref.read(hostsProvider.notifier).save(
            host,
            password: isPassword && _password.text.isNotEmpty
                ? _password.text
                : null,
            privateKey: !isPassword ? _loadedKey : null,
            // Key baru (dimuat/dibuat) → passphrase ikut diganti, termasuk
            // dikosongkan, agar passphrase key lama tidak terbawa.
            passphrase: isPassword
                ? null
                : (_passphrase.text.isNotEmpty
                    ? _passphrase.text
                    : (_loadedKey != null ? '' : null)),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveError = describeSaveError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.dns_outlined,
                        color: AppTheme.accent, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      _isEdit ? 'Edit Host' : 'Host Baru',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _LabeledField(
                  label: 'Nama (label)',
                  controller: _label,
                  hint: 'mis. Server Produksi',
                ),
                const SizedBox(height: 14),
                _tagField(),
                const SizedBox(height: 14),
                _osPicker(),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: _LabeledField(
                        label: 'Host / IP',
                        controller: _host,
                        hint: 'mis. 192.168.1.10',
                        validator: _required,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: _LabeledField(
                        label: 'Port',
                        controller: _port,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _LabeledField(
                  label: 'Username',
                  controller: _user,
                  hint: 'mis. root',
                  validator: _required,
                ),
                const SizedBox(height: 18),
                _authMethodToggle(),
                const SizedBox(height: 14),
                if (_method == SshAuthMethod.password)
                  _passwordFields()
                else
                  _keyFields(),
                const SizedBox(height: 18),
                _jumpHostPicker(),
                const SizedBox(height: 14),
                _LabeledField(
                  label: 'Startup command (opsional)',
                  controller: _startup,
                  hint: 'mis. cd /var/www && ls',
                ),
                const SizedBox(height: 14),
                _persistentToggle(),
                if (_saveError != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.danger.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppTheme.rSm),
                      border: Border.all(
                          color: AppTheme.danger.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      _saveError!,
                      style: TextStyle(
                          color: AppTheme.danger, fontSize: 12),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: Text('Batal',
                          style: TextStyle(color: AppTheme.textMuted)),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _saving ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.accent,
                        foregroundColor: AppTheme.onAccent,
                      ),
                      child: _saving
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppTheme.onAccent),
                            )
                          : const Text('Simpan'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _authMethodToggle() {
    Widget option(SshAuthMethod m, IconData icon, String text) {
      final selected = _method == m;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _method = m),
          borderRadius: BorderRadius.circular(AppTheme.rSm),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? AppTheme.accent.withValues(alpha: 0.15)
                  : AppTheme.surfaceInput,
              borderRadius: BorderRadius.circular(AppTheme.rSm),
              border: Border.all(
                color: selected ? AppTheme.accent : AppTheme.border,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 15,
                    color: selected ? AppTheme.accent : AppTheme.textMuted),
                const SizedBox(width: 6),
                Text(
                  text,
                  style: TextStyle(
                    color: selected ? AppTheme.accent : AppTheme.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        option(SshAuthMethod.password, Icons.password, 'Password'),
        const SizedBox(width: 10),
        option(SshAuthMethod.key, Icons.vpn_key_outlined, 'SSH Key'),
      ],
    );
  }

  /// Toggle "sesi persisten via tmux" — gaya kartu agar jelas ini fitur khusus.
  Widget _persistentToggle() {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.rSm),
      onTap: () => setState(() => _persistent = !_persistent),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.surfaceInput,
          borderRadius: BorderRadius.circular(AppTheme.rSm),
          border: Border.all(
            color: _persistent
                ? AppTheme.accent.withValues(alpha: 0.6)
                : AppTheme.border,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.auto_mode_rounded,
                size: 18,
                color: _persistent ? AppTheme.accent : AppTheme.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Sesi persisten (tmux)',
                      style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                      'Program tetap hidup saat koneksi putus; sambung ulang '
                      'melanjutkan sesi. Butuh tmux di server.',
                      style:
                          TextStyle(color: AppTheme.textMuted, fontSize: 11.5)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Switch(
              value: _persistent,
              onChanged: (v) => setState(() => _persistent = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _osPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.dvr_outlined, size: 14, color: AppTheme.textMuted),
            const SizedBox(width: 6),
            Text('Sistem operasi (ikon & warna)',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.surfaceInput,
            borderRadius: BorderRadius.circular(AppTheme.rSm),
            border: Border.all(color: AppTheme.border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<HostOs>(
              value: _os,
              isExpanded: true,
              dropdownColor: AppTheme.surfaceHigh,
              icon: Icon(Icons.arrow_drop_down, color: AppTheme.textMuted),
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 14),
              items: [
                for (final o in HostOs.values)
                  DropdownMenuItem<HostOs>(
                    value: o,
                    child: Row(
                      children: [
                        Icon(o.icon,
                            size: 16,
                            color: o == HostOs.auto
                                ? AppTheme.textMuted
                                : o.color),
                        const SizedBox(width: 10),
                        Text(o.label),
                      ],
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _os = v ?? HostOs.auto),
            ),
          ),
        ),
      ],
    );
  }

  Widget _tagField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.sell_outlined, size: 13, color: AppTheme.textMuted),
            const SizedBox(width: 6),
            Text('Tag (opsional)',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          decoration: BoxDecoration(
            color: AppTheme.surfaceInput,
            borderRadius: BorderRadius.circular(AppTheme.rSm),
            border: Border.all(color: AppTheme.border),
          ),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final t in _tags)
                Container(
                  padding: const EdgeInsets.fromLTRB(9, 4, 5, 4),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppTheme.rPill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(t,
                          style: TextStyle(
                              color: AppTheme.accent,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(width: 3),
                      InkWell(
                        onTap: () => setState(() => _tags.remove(t)),
                        borderRadius: BorderRadius.circular(AppTheme.rPill),
                        child: Icon(Icons.close_rounded,
                            size: 13, color: AppTheme.accent),
                      ),
                    ],
                  ),
                ),
              IntrinsicWidth(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 90),
                  child: TextField(
                    controller: _tagInput,
                    style:
                        TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 4),
                      hintText: _tags.isEmpty ? 'tambah tag…' : '+ tag',
                      hintStyle:
                          TextStyle(color: AppTheme.textFaint, fontSize: 12.5),
                    ),
                    onChanged: (v) {
                      // Koma atau spasi memisah tag.
                      if (v.endsWith(',') || v.endsWith(' ')) {
                        _addTag(v.substring(0, v.length - 1));
                      }
                    },
                    onSubmitted: _addTag,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _jumpHostPicker() {
    final hostsAsync = ref.watch(hostsProvider);
    final all = hostsAsync.asData?.value ?? const <SshHost>[];
    // Jangan boleh pilih diri sendiri sebagai bastion.
    final options = all.where((h) => h.id != widget.existing?.id).toList();
    // Bila jump yang tersimpan sudah tak ada, reset agar tak dangling.
    if (_jumpHostId != null && !options.any((h) => h.id == _jumpHostId)) {
      _jumpHostId = null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.alt_route, size: 14, color: AppTheme.textMuted),
            const SizedBox(width: 6),
            Text('Jump host / bastion (opsional)',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.surfaceInput,
            borderRadius: BorderRadius.circular(AppTheme.rSm),
            border: Border.all(color: AppTheme.border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: _jumpHostId,
              isExpanded: true,
              dropdownColor: AppTheme.surfaceHigh,
              icon: Icon(Icons.arrow_drop_down, color: AppTheme.textMuted),
              style:
                  TextStyle(color: AppTheme.textPrimary, fontSize: 14),
              hint: Text('Koneksi langsung (tanpa bastion)',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Koneksi langsung (tanpa bastion)',
                      style:
                          TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                ),
                for (final h in options)
                  DropdownMenuItem<String?>(
                    value: h.id,
                    child: Text('${h.label}  ·  ${h.subtitle}',
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() => _jumpHostId = v),
            ),
          ),
        ),
        if (options.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Simpan host lain dulu untuk dipakai sebagai bastion.',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
            ),
          ),
      ],
    );
  }

  Widget _passwordFields() {
    return _LabeledField(
      label: _isEdit ? 'Password (kosongkan = tak diubah)' : 'Password',
      controller: _password,
      obscure: _obscure,
      suffix: IconButton(
        icon: Icon(
          _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          size: 18,
          color: AppTheme.textMuted,
        ),
        onPressed: () => setState(() => _obscure = !_obscure),
      ),
    );
  }

  Widget _keyFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: _LabeledField(
                label: 'Path private key',
                controller: _keyPath,
                hint: '/Users/kamu/.ssh/id_ed25519',
              ),
            ),
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: OutlinedButton(
                onPressed: _loadKeyFile,
                child: const Text('Muat'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                'Belum punya key? Buat pasangan baru di sini.',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11.5),
              ),
            ),
            TextButton.icon(
              onPressed: _generateKey,
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.accent,
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              icon: const Icon(Icons.add_moderator_outlined, size: 15),
              label: const Text('Buat key baru (ed25519)'),
            ),
          ],
        ),
        if (_keyStatus != null) ...[
          const SizedBox(height: 8),
          Text(
            _keyStatus!,
            style: TextStyle(
              color: _keyStatus!.startsWith('✓')
                  ? AppTheme.success
                  : AppTheme.danger,
              fontSize: 12,
            ),
          ),
        ],
        const SizedBox(height: 14),
        _LabeledField(
          label: 'Passphrase key (opsional)',
          controller: _passphrase,
          obscure: true,
          onChanged: (_) => _refreshPublicKey(),
        ),
        if (_publicKey != null) ...[
          const SizedBox(height: 14),
          PublicKeyPanel(info: _publicKey!, onInstall: _installKey),
        ] else if (_publicKeyError != null) ...[
          const SizedBox(height: 10),
          Text(_publicKeyError!,
              style: TextStyle(color: AppTheme.warning, fontSize: 12)),
        ],
        const SizedBox(height: 14),
        _agentToggle(),
      ],
    );
  }

  /// Toggle agent forwarding — dengan peringatan karena ada implikasi keamanan.
  Widget _agentToggle() {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.rSm),
      onTap: () => setState(() => _forwardAgent = !_forwardAgent),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.surfaceInput,
          borderRadius: BorderRadius.circular(AppTheme.rSm),
          border: Border.all(
            color: _forwardAgent
                ? AppTheme.warning.withValues(alpha: 0.6)
                : AppTheme.border,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.forward_rounded,
                size: 18,
                color: _forwardAgent ? AppTheme.warning : AppTheme.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Agent forwarding',
                      style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                      'Dari server ini kamu bisa ssh/git ke mesin lain memakai '
                      'key ini, tanpa menyalin key-nya. Aktifkan hanya untuk '
                      'server yang kamu percaya.',
                      style:
                          TextStyle(color: AppTheme.textMuted, fontSize: 11.5)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Switch(
              value: _forwardAgent,
              onChanged: (v) => setState(() => _forwardAgent = v),
            ),
          ],
        ),
      ),
    );
  }

  static String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null;
}

/// Field berlabel dengan gaya seragam.
class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.controller,
    this.hint,
    this.obscure = false,
    this.keyboardType,
    this.validator,
    this.suffix,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          validator: validator,
          onChanged: onChanged,
          style: TextStyle(color: AppTheme.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle:
                TextStyle(color: AppTheme.textFaint, fontSize: 13),
            isDense: true,
            filled: true,
            fillColor: AppTheme.surfaceInput,
            suffixIcon: suffix,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.rSm),
              borderSide: BorderSide(color: AppTheme.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.rSm),
              borderSide: BorderSide(color: AppTheme.accent),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.rSm),
              borderSide: BorderSide(color: AppTheme.danger),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.rSm),
              borderSide: BorderSide(color: AppTheme.danger),
            ),
          ),
        ),
      ],
    );
  }
}

/// Pesan galat penyimpanan yang bisa dipahami pengguna.
String describeSaveError(Object e) {
  final text = e.toString();
  // -25293 errSecAuthFailed, -25308 errSecInteractionNotAllowed,
  // -128 userCanceled, -25300 errSecItemNotFound, -34018 missing entitlement.
  if (text.contains('-25293')) {
    return 'Keychain macOS menolak akses, jadi host belum disimpan. Biasanya '
        'ini terjadi bila app diperbarui/dibangun ulang saat masih terbuka. '
        'Tutup HegiKetok sepenuhnya lalu buka lagi, kemudian simpan ulang.';
  }
  if (text.contains('-25308')) {
    return 'Keychain sedang terkunci, jadi host belum disimpan. Buka kunci '
        'Mac/Keychain lalu coba lagi.';
  }
  if (text.contains('-128')) {
    return 'Akses Keychain dibatalkan, jadi host belum disimpan. Pilih '
        '"Always Allow" saat macOS meminta izin.';
  }
  if (text.contains('security result code') ||
      text.contains('PlatformException')) {
    return 'Keychain macOS gagal menyimpan rahasia, jadi host belum disimpan. '
        'Coba tutup dan buka ulang HegiKetok.\n($text)';
  }
  if (e is FormatException) {
    return 'Berkas daftar host (hosts.json) rusak, jadi tidak ditimpa. '
        'Pulihkan dari backup lewat Settings → Restore.';
  }
  return 'Gagal menyimpan: $text';
}
