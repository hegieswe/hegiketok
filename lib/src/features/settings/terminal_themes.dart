import 'package:material_ui/material_ui.dart';
import 'package:xterm/xterm.dart';

/// Sebuah preset tema warna terminal (palet ANSI lengkap) + nama tampilan.
class TerminalThemePreset {
  const TerminalThemePreset(this.name, this.theme);

  final String name;
  final TerminalTheme theme;

  Color get background => theme.background;
  Color get foreground => theme.foreground;

  /// Warna contoh untuk pratinjau kartu tema.
  List<Color> get swatches => [
        theme.red,
        theme.green,
        theme.yellow,
        theme.blue,
        theme.magenta,
        theme.cyan,
      ];
}

Color _h(String hex) => Color(int.parse('FF$hex', radix: 16));

TerminalTheme _mk({
  required String bg,
  required String fg,
  required String cur,
  required String sel,
  required String bl,
  required String r,
  required String g,
  required String y,
  required String b,
  required String m,
  required String c,
  required String w,
  required String bbl,
  required String br,
  required String bgr,
  required String by,
  required String bb,
  required String bm,
  required String bc,
  required String bw,
}) {
  return TerminalTheme(
    cursor: _h(cur),
    selection: _h(sel).withValues(alpha: 0.40),
    foreground: _h(fg),
    background: _h(bg),
    black: _h(bl),
    red: _h(r),
    green: _h(g),
    yellow: _h(y),
    blue: _h(b),
    magenta: _h(m),
    cyan: _h(c),
    white: _h(w),
    brightBlack: _h(bbl),
    brightRed: _h(br),
    brightGreen: _h(bgr),
    brightYellow: _h(by),
    brightBlue: _h(bb),
    brightMagenta: _h(bm),
    brightCyan: _h(bc),
    brightWhite: _h(bw),
    searchHitBackground: _h('ffd54f'),
    searchHitBackgroundCurrent: _h('ffb300'),
    searchHitForeground: _h(bg),
  );
}

/// Katalog tema bawaan. Yang pertama adalah default.
const kDefaultThemeName = 'HegiKetok Dark';

final List<TerminalThemePreset> kTerminalThemes = [
  TerminalThemePreset(
    'HegiKetok Dark',
    _mk(
      bg: '0d1117', fg: 'e6edf3', cur: '2f81f7', sel: '2f81f7',
      bl: '484f58', r: 'ff7b72', g: '3fb950', y: 'd29922', b: '58a6ff',
      m: 'bc8cff', c: '39c5cf', w: 'b1bac4',
      bbl: '6e7681', br: 'ffa198', bgr: '56d364', by: 'e3b341', bb: '79c0ff',
      bm: 'd2a8ff', bc: '56d4dd', bw: 'ffffff',
    ),
  ),
  TerminalThemePreset(
    'Dracula',
    _mk(
      bg: '282a36', fg: 'f8f8f2', cur: 'f8f8f2', sel: '44475a',
      bl: '21222c', r: 'ff5555', g: '50fa7b', y: 'f1fa8c', b: 'bd93f9',
      m: 'ff79c6', c: '8be9fd', w: 'f8f8f2',
      bbl: '6272a4', br: 'ff6e6e', bgr: '69ff94', by: 'ffffa5', bb: 'd6acff',
      bm: 'ff92df', bc: 'a4ffff', bw: 'ffffff',
    ),
  ),
  TerminalThemePreset(
    'Nord',
    _mk(
      bg: '2e3440', fg: 'd8dee9', cur: 'd8dee9', sel: '434c5e',
      bl: '3b4252', r: 'bf616a', g: 'a3be8c', y: 'ebcb8b', b: '81a1c1',
      m: 'b48ead', c: '88c0d0', w: 'e5e9f0',
      bbl: '4c566a', br: 'bf616a', bgr: 'a3be8c', by: 'ebcb8b', bb: '81a1c1',
      bm: 'b48ead', bc: '8fbcbb', bw: 'eceff4',
    ),
  ),
  TerminalThemePreset(
    'Catppuccin Mocha',
    _mk(
      bg: '1e1e2e', fg: 'cdd6f4', cur: 'f5e0dc', sel: '585b70',
      bl: '45475a', r: 'f38ba8', g: 'a6e3a1', y: 'f9e2af', b: '89b4fa',
      m: 'f5c2e7', c: '94e2d5', w: 'bac2de',
      bbl: '585b70', br: 'f38ba8', bgr: 'a6e3a1', by: 'f9e2af', bb: '89b4fa',
      bm: 'f5c2e7', bc: '94e2d5', bw: 'a6adc8',
    ),
  ),
  TerminalThemePreset(
    'Tokyo Night',
    _mk(
      bg: '1a1b26', fg: 'c0caf5', cur: 'c0caf5', sel: '283457',
      bl: '15161e', r: 'f7768e', g: '9ece6a', y: 'e0af68', b: '7aa2f7',
      m: 'bb9af7', c: '7dcfff', w: 'a9b1d6',
      bbl: '414868', br: 'f7768e', bgr: '9ece6a', by: 'e0af68', bb: '7aa2f7',
      bm: 'bb9af7', bc: '7dcfff', bw: 'c0caf5',
    ),
  ),
  TerminalThemePreset(
    'Gruvbox Dark',
    _mk(
      bg: '282828', fg: 'ebdbb2', cur: 'ebdbb2', sel: '504945',
      bl: '282828', r: 'cc241d', g: '98971a', y: 'd79921', b: '458588',
      m: 'b16286', c: '689d6a', w: 'a89984',
      bbl: '928374', br: 'fb4934', bgr: 'b8bb26', by: 'fabd2f', bb: '83a598',
      bm: 'd3869b', bc: '8ec07c', bw: 'ebdbb2',
    ),
  ),
  TerminalThemePreset(
    'Everforest Dark',
    _mk(
      bg: '2d353b', fg: 'd3c6aa', cur: 'd3c6aa', sel: '543a48',
      bl: '475258', r: 'e67e80', g: 'a7c080', y: 'dbbc7f', b: '7fbbb3',
      m: 'd699b6', c: '83c092', w: 'd3c6aa',
      bbl: '475258', br: 'e67e80', bgr: 'a7c080', by: 'dbbc7f', bb: '7fbbb3',
      bm: 'd699b6', bc: '83c092', bw: 'd3c6aa',
    ),
  ),
  TerminalThemePreset(
    'Night Owl',
    _mk(
      bg: '011627', fg: 'd6deeb', cur: '80a4c2', sel: '1d3b53',
      bl: '011627', r: 'ef5350', g: '22da6e', y: 'c5e478', b: '82aaff',
      m: 'c792ea', c: '21c7a8', w: 'ffffff',
      bbl: '575656', br: 'ef5350', bgr: '22da6e', by: 'ffeb95', bb: '82aaff',
      bm: 'c792ea', bc: '7fdbca', bw: 'ffffff',
    ),
  ),
  TerminalThemePreset(
    'One Dark',
    _mk(
      bg: '282c34', fg: 'abb2bf', cur: '528bff', sel: '3e4451',
      bl: '282c34', r: 'e06c75', g: '98c379', y: 'e5c07b', b: '61afef',
      m: 'c678dd', c: '56b6c2', w: 'abb2bf',
      bbl: '5c6370', br: 'e06c75', bgr: '98c379', by: 'e5c07b', bb: '61afef',
      bm: 'c678dd', bc: '56b6c2', bw: 'ffffff',
    ),
  ),
];

TerminalThemePreset themeByName(String name) {
  return kTerminalThemes.firstWhere(
    (t) => t.name == name,
    orElse: () => kTerminalThemes.first,
  );
}
