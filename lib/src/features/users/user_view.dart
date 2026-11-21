import 'package:material_ui/material_ui.dart';

import '../../ssh/handshake_stepper.dart';
import '../../theme/app_theme.dart';
import '../../theme/ui.dart';
import 'user_controller.dart';
import 'user_models.dart';

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
    return PanelHeader(
      icon: Icons.group_outlined,
      title: 'Users',
      meta: '${c.users.length} user · $online online · $sudoers admin',
      actions: [
        GhostIconButton(
          icon: Icons.refresh_rounded,
          tooltip: 'Perbarui',
          busy: c.refreshing,
          onTap: c.refresh,
        ),
      ],
    );
  }

  Widget _filterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppTheme.bg,
      child: Row(
        children: [
          Expanded(
            child: SearchField(
              hint: 'Cari user…',
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          const SizedBox(width: 10),
          FilterTab(
            label: 'Semua',
            active: _filter == _Filter.all,
            onTap: () => setState(() => _filter = _Filter.all),
          ),
          const SizedBox(width: 6),
          FilterTab(
            label: 'Manusia',
            active: _filter == _Filter.human,
            onTap: () => setState(() => _filter = _Filter.human),
          ),
          const SizedBox(width: 6),
          FilterTab(
            label: 'Sistem',
            active: _filter == _Filter.system,
            onTap: () => setState(() => _filter = _Filter.system),
          ),
        ],
      ),
    );
  }

  Widget _list() {
    final items = _visible();
    if (items.isEmpty) {
      return const PanelMessage(
        icon: Icons.group_outlined,
        message: 'Tidak ada user yang cocok.',
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
    return PanelMessage(
      icon: icon,
      message: msg,
      iconColor: AppTheme.warning,
      onAction: onRetry,
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
    return AppCard(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 8),
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
                  color: u.isRoot ? AppTheme.warning : AppTheme.textMuted,
                ),
              ),
              if (u.loggedIn)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: StatusDot(AppTheme.success),
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
                    if (u.isRoot)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Pill('root', color: AppTheme.warning),
                      ),
                    if (u.isSudoer && !u.isRoot)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Pill('sudo', color: AppTheme.violet),
                      ),
                    if (!u.canLogin)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Pill('no-login', color: AppTheme.textFaint),
                      ),
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
              Tag('uid ${u.uid}', mono: true),
              const SizedBox(height: 4),
              Tag('gid ${u.gid}', mono: true),
            ],
          ),
        ],
      ),
    );
  }
}
