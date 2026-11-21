import 'package:material_ui/material_ui.dart';

import '../../ssh/handshake_stepper.dart';
import '../../theme/app_theme.dart';
import 'user_controller.dart';
import 'user_models.dart';

const _green = Color(0xFF3FB950);
const _amber = Color(0xFFD29922);
const _purple = Color(0xFFBC8CFF);

enum _Filter { all, human, system }

/// Panel daftar user sistem (read-only): login, shell, sudo, grup.
class UserView extends StatefulWidget {
  const UserView({super.key, required this.controller});

  final UserController controller;

  @override
  State<UserView> createState() => _UserViewState();
}

class _UserViewState extends State<UserView> {
  String _query = '';
  _Filter _filter = _Filter.all;

  UserController get c => widget.controller;

  List<SystemUser> _visible() {
    return c.users.where((u) {
      switch (_filter) {
        case _Filter.human:
          if (!u.isHuman) return false;
          break;
        case _Filter.system:
          if (!u.isSystem) return false;
          break;
        case _Filter.all:
          break;
      }
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return u.name.toLowerCase().contains(q) ||
          u.gecos.toLowerCase().contains(q) ||
          u.uid.toString() == q;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        if (c.loading && c.snapshot == null && !c.progress.finished) {
          return HandshakeLoading(
            progress: c.progress,
            title: 'Menyambungkan ke ${c.credentials.label}…',
          );
        }
        if (c.connectError != null && c.snapshot == null) {
          return _errorState(c.connectError!, c.connect);
        }
        if (c.loading && c.snapshot == null) {
          return _Centered(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppTheme.accent),
            ),
          );
        }
        final snap = c.snapshot!;
        if (snap.error != null && c.users.isEmpty) {
          return _errorState(snap.error!, c.refresh, icon: Icons.group_outlined);
        }
        return Container(
          color: AppTheme.bg,
          child: Column(
            children: [
              _header(),
              Divider(height: 1, color: AppTheme.border),
              _filterBar(),
              Expanded(child: _list()),
            ],
          ),
        );
      },
    );
  }

  Widget _header() {
    final online = c.users.where((u) => u.loggedIn).length;
    final sudoers = c.users.where((u) => u.isSudoer || u.isRoot).length;
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: AppTheme.surface,
      child: Row(
        children: [
          Icon(Icons.group_outlined, size: 20, color: AppTheme.accent),
          const SizedBox(width: 10),
          Text('Users',
              style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 10),
          Text('${c.users.length} user · $online online · $sudoers admin',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
          const Spacer(),
          IconButton(
            onPressed: c.refreshing ? null : c.refresh,
            tooltip: 'Perbarui',
            icon: c.refreshing
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppTheme.accent))
                : Icon(Icons.refresh, size: 18, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _filterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppTheme.bg,
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 34,
              child: TextField(
                style:
                    TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: AppTheme.surface,
                  hintText: 'Cari user…',
                  hintStyle:
                      TextStyle(color: AppTheme.textMuted, fontSize: 13),
                  prefixIcon: Icon(Icons.search,
                      size: 16, color: AppTheme.textMuted),
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: AppTheme.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: AppTheme.accent),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _filterChip('Semua', _Filter.all),
          const SizedBox(width: 6),
          _filterChip('Manusia', _Filter.human),
          const SizedBox(width: 6),
          _filterChip('Sistem', _Filter.system),
        ],
      ),
    );
  }

  Widget _filterChip(String label, _Filter f) {
    final active = _filter == f;
    return InkWell(
      onTap: () => setState(() => _filter = f),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? AppTheme.accent.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? AppTheme.accent : AppTheme.border),
        ),
        child: Text(label,
            style: TextStyle(
                color: active ? AppTheme.accent : AppTheme.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w500)),
      ),
    );
  }

  Widget _list() {
    final items = _visible();
    if (items.isEmpty) {
      return _Centered(
        child: Text('Tidak ada user yang cocok.',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemCount: items.length,
      itemBuilder: (_, i) => _UserCard(user: items[i]),
    );
  }

  Widget _errorState(String msg, VoidCallback onRetry,
      {IconData icon = Icons.error_outline}) {
    return _Centered(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _amber, size: 38),
          const SizedBox(height: 12),
          SizedBox(
            width: 360,
            child: Text(msg,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 15),
            label: const Text('Coba lagi'),
          ),
        ],
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      Container(color: AppTheme.bg, child: Center(child: child));
}

class _UserCard extends StatelessWidget {
  const _UserCard({required this.user});
  final SystemUser user;

  @override
  Widget build(BuildContext context) {
    final u = user;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: AppTheme.bg,
                child: Icon(
                  u.isRoot ? Icons.shield : Icons.person_outline,
                  size: 17,
                  color: u.isRoot ? _amber : AppTheme.textMuted,
                ),
              ),
              if (u.loggedIn)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _green,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.surface, width: 2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(u.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 8),
                    if (u.isRoot) _badge('root', _amber),
                    if (u.isSudoer && !u.isRoot) _badge('sudo', _purple),
                    if (!u.canLogin) _badge('no-login', AppTheme.textMuted),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${u.gecos.isEmpty ? u.home : u.gecos} · ${u.shell}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 11,
                      fontFamily: 'Menlo'),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('uid ${u.uid}',
                  style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 11,
                      fontFamily: 'Menlo')),
              Text('gid ${u.gid}',
                  style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 11,
                      fontFamily: 'Menlo')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(text, style: TextStyle(color: color, fontSize: 10)),
      ),
    );
  }
}
