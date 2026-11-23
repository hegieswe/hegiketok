import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_term/src/data/host_credentials.dart';
import 'package:nexus_term/src/models/ssh_host.dart';

SshHost _h(String id,
        {String? jump,
        SshAuthMethod auth = SshAuthMethod.key,
        bool forwardAgent = false}) =>
    SshHost(
      id: id,
      label: id,
      host: '$id.test',
      username: 'u-$id',
      authMethod: auth,
      jumpHostId: jump,
      forwardAgent: forwardAgent,
    );

Future<HostSecret> _secrets(String id) async => HostSecret(
    password: 'pw-$id', privateKey: 'KEY-$id', passphrase: 'pass-$id');

void main() {
  test('host key: hanya private key yang dibawa; password dikosongkan',
      () async {
    final c = await buildHostCredentials(_h('a'),
        loadSecret: _secrets, allHosts: const []);
    expect(c.host, 'a.test');
    expect(c.privateKey, 'KEY-a');
    expect(c.password, isNull);
    expect(c.jumpHosts, isEmpty);
  });

  test('host password: hanya password yang dibawa', () async {
    final c = await buildHostCredentials(
        _h('a', auth: SshAuthMethod.password),
        loadSecret: _secrets,
        allHosts: const []);
    expect(c.password, 'pw-a');
    expect(c.privateKey, isNull);
  });

  test('rantai bastion urut dari yang paling luar', () async {
    final all = [_h('target', jump: 'mid'), _h('mid', jump: 'edge'), _h('edge')];
    final c = await buildHostCredentials(all[0],
        loadSecret: _secrets, allHosts: all);
    expect(c.jumpHosts.map((j) => j.host), ['edge.test', 'mid.test']);
    expect(c.jumpHosts.every((j) => j.jumpHosts.isEmpty), isTrue);
  });

  test('referensi melingkar tidak membuat loop tak berujung', () async {
    final all = [_h('a', jump: 'b'), _h('b', jump: 'a')];
    final c = await buildHostCredentials(all[0],
        loadSecret: _secrets, allHosts: all);
    expect(c.jumpHosts.map((j) => j.host), ['b.test']);
  });

  test('bastion yang sudah dihapus dilewati', () async {
    final c = await buildHostCredentials(_h('a', jump: 'hilang'),
        loadSecret: _secrets, allHosts: [_h('a', jump: 'hilang')]);
    expect(c.jumpHosts, isEmpty);
  });

  group('agent forwarding', () {
    test('hanya untuk host tujuan, tidak pernah untuk bastion', () async {
      final all = [
        _h('target', jump: 'edge', forwardAgent: true),
        _h('edge', forwardAgent: true),
      ];
      final c = await buildHostCredentials(all[0],
          loadSecret: _secrets, allHosts: all);
      expect(c.forwardAgent, isTrue);
      expect(c.jumpHosts.single.forwardAgent, isFalse);
    });

    test('diabaikan untuk host ber-password', () async {
      final c = await buildHostCredentials(
          _h('a', auth: SshAuthMethod.password, forwardAgent: true),
          loadSecret: _secrets,
          allHosts: const []);
      expect(c.forwardAgent, isFalse);
    });

    test('mati secara bawaan', () async {
      final c = await buildHostCredentials(_h('a'),
          loadSecret: _secrets, allHosts: const []);
      expect(c.forwardAgent, isFalse);
    });
  });

  test('resolveJumpChain: null → kosong; visited mencegah diri sendiri',
      () async {
    expect(
        await resolveJumpChain(null, loadSecret: _secrets, allHosts: const []),
        isEmpty);
    final all = [_h('a'), _h('b', jump: 'a')];
    final chain = await resolveJumpChain('b',
        loadSecret: _secrets, allHosts: all, visited: {'a'});
    // 'a' sedang diedit (visited) → b tidak boleh melompat balik lewat a.
    expect(chain.map((j) => j.host), ['b.test']);
  });

  group('SshHost.forwardAgent', () {
    test('bawaan false; JSON lama tanpa field → false', () {
      expect(_h('a').forwardAgent, isFalse);
      final json = _h('a').toJson()..remove('forwardAgent');
      expect(SshHost.fromJson(json).forwardAgent, isFalse);
    });

    test('round-trip JSON & copyWith', () {
      final on = _h('a').copyWith(forwardAgent: true);
      expect(on.forwardAgent, isTrue);
      expect(SshHost.fromJson(on.toJson()).forwardAgent, isTrue);
      expect(on.copyWith(label: 'x').forwardAgent, isTrue);
    });
  });
}
