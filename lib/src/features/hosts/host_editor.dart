import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import '../../data/host_providers.dart';
import '../../models/ssh_host.dart';
import '../../theme/app_theme.dart';

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

  SshAuthMethod _method = SshAuthMethod.password;
  String? _jumpHostId;
  bool _obscure = true;

  // Konten private key yang sudah dimuat dari file (jika ada).
  String? _loadedKey;
  String? _keyStatus;
  String? _saveError;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

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
    } catch (e) {
      setState(() {
        _loadedKey = null;
        _keyStatus = '✗ Gagal membaca file: periksa path';
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // Validasi khusus metode key saat membuat host baru.
    if (_method == SshAuthMethod.key && !_isEdit && _loadedKey == null) {
      setState(() => _keyStatus = '✗ Muat file private key dulu');
      return;
    }

    setState(() {
      _saving = true;
      _saveError = null;
    });

    final host = (widget.existing ??
            SshHost(
              id: const Uuid().v4(),
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
    );

    final isPassword = _method == SshAuthMethod.password;
    try {
      await ref.read(hostsProvider.notifier).save(
            host,
            password: isPassword && _password.text.isNotEmpty
                ? _password.text
                : null,
            privateKey: !isPassword ? _loadedKey : null,
            passphrase: !isPassword && _passphrase.text.isNotEmpty
                ? _passphrase.text
                : null,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveError = 'Gagal menyimpan: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppTheme.border),
      ),
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
                    const Icon(Icons.dns_outlined,
                        color: AppTheme.accent, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      _isEdit ? 'Edit Host' : 'Host Baru',
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
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
                if (_saveError != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF7B72).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: const Color(0xFFFF7B72).withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      _saveError!,
                      style: const TextStyle(
                          color: Color(0xFFFF7B72), fontSize: 12),
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
                      child: const Text('Batal',
                          style: TextStyle(color: AppTheme.textMuted)),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _saving ? null : _submit,
                      style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.accent),
                      child: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
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
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? AppTheme.accent.withValues(alpha: 0.15)
                  : AppTheme.bg,
              borderRadius: BorderRadius.circular(8),
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
                    fontWeight: FontWeight.w500,
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
            const Icon(Icons.alt_route, size: 14, color: AppTheme.textMuted),
            const SizedBox(width: 6),
            const Text('Jump host / bastion (opsional)',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: _jumpHostId,
              isExpanded: true,
              dropdownColor: AppTheme.surface,
              icon: const Icon(Icons.arrow_drop_down, color: AppTheme.textMuted),
              style:
                  const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
              hint: const Text('Koneksi langsung (tanpa bastion)',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
              items: [
                const DropdownMenuItem<String?>(
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
          const Padding(
            padding: EdgeInsets.only(top: 6),
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
        if (_keyStatus != null) ...[
          const SizedBox(height: 8),
          Text(
            _keyStatus!,
            style: TextStyle(
              color: _keyStatus!.startsWith('✓')
                  ? AppTheme.success
                  : const Color(0xFFFF7B72),
              fontSize: 12,
            ),
          ),
        ],
        const SizedBox(height: 14),
        _LabeledField(
          label: 'Passphrase key (opsional)',
          controller: _passphrase,
          obscure: true,
        ),
      ],
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
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          validator: validator,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle:
                const TextStyle(color: AppTheme.textMuted, fontSize: 13),
            isDense: true,
            filled: true,
            fillColor: AppTheme.bg,
            suffixIcon: suffix,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppTheme.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppTheme.accent),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFFF7B72)),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFFF7B72)),
            ),
          ),
        ),
      ],
    );
  }
}
