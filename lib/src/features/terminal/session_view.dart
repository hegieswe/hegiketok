import 'package:material_ui/material_ui.dart';
import 'package:xterm/xterm.dart';

/// Widget yang menampilkan satu [Terminal] dengan tema warna aplikasi.
/// Dipakai ulang oleh sesi lokal maupun SSH.
class SessionView extends StatelessWidget {
  const SessionView(this.terminal, {super.key});

  final Terminal terminal;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: TerminalView(
        terminal,
        autofocus: true,
        padding: const EdgeInsets.all(8),
        theme: nexusTerminalTheme,
        textStyle: const TerminalStyle(
          fontSize: 14,
          fontFamily: 'Menlo',
        ),
      ),
    );
  }
}

/// Palet warna terminal (ANSI) senada dengan tema gelap aplikasi.
const nexusTerminalTheme = TerminalTheme(
  cursor: Color(0xFF2F81F7),
  selection: Color(0x402F81F7),
  foreground: Color(0xFFE6EDF3),
  background: Color(0xFF0D1117),
  black: Color(0xFF484F58),
  red: Color(0xFFFF7B72),
  green: Color(0xFF3FB950),
  yellow: Color(0xFFD29922),
  blue: Color(0xFF58A6FF),
  magenta: Color(0xFFBC8CFF),
  cyan: Color(0xFF39C5CF),
  white: Color(0xFFB1BAC4),
  brightBlack: Color(0xFF6E7681),
  brightRed: Color(0xFFFFA198),
  brightGreen: Color(0xFF56D364),
  brightYellow: Color(0xFFE3B341),
  brightBlue: Color(0xFF79C0FF),
  brightMagenta: Color(0xFFD2A8FF),
  brightCyan: Color(0xFF56D4DD),
  brightWhite: Color(0xFFFFFFFF),
  searchHitBackground: Color(0xFFD29922),
  searchHitBackgroundCurrent: Color(0xFFE3B341),
  searchHitForeground: Color(0xFF0D1117),
);
