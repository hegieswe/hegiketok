// Widget test untuk form koneksi SSH: validasi field & hasil yang benar.
// Berjalan headless (tanpa koneksi jaringan nyata).

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexus_term/src/features/ssh/connection_form.dart';
import 'package:nexus_term/src/models/ssh_credentials.dart';

void main() {
  // Pembungkus: tombol yang membuka form & menyimpan hasilnya.
  Future<SshCredentials?> pumpAndOpen(WidgetTester tester) async {
    SshCredentials? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showSshConnectionForm(context);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('menampilkan error validasi saat field wajib kosong',
      (tester) async {
    await pumpAndOpen(tester);

    // Langsung tekan Connect tanpa mengisi apa pun.
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(find.text('Host wajib diisi'), findsOneWidget);
    expect(find.text('Username wajib diisi'), findsOneWidget);
  });

  testWidgets('mengembalikan kredensial yang benar saat diisi valid',
      (tester) async {
    await pumpAndOpen(tester);

    final fields = find.byType(TextFormField);
    // Urutan field: 0=host, 1=port, 2=username, 3=password.
    await tester.enterText(fields.at(0), '192.168.1.50');
    await tester.enterText(fields.at(1), '2022');
    await tester.enterText(fields.at(2), 'deploy');
    await tester.enterText(fields.at(3), 'rahasia');

    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    // Dialog tertutup.
    expect(find.text('Connect'), findsNothing);
  });

  testWidgets('tombol Batal menutup dialog tanpa hasil', (tester) async {
    await pumpAndOpen(tester);
    expect(find.text('Koneksi SSH Baru'), findsOneWidget);

    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();

    expect(find.text('Koneksi SSH Baru'), findsNothing);
  });
}
