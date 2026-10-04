import 'package:flutter/material.dart';

import 'db.dart';
import 'home_pages.dart';
import 'prefs.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Prefs.load();
  runApp(const KjvApp());
}

ThemeData _theme(int mode, Brightness phone) {
  final dark = mode == 3 || (mode == 0 && phone == Brightness.dark);
  if (dark) {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorSchemeSeed: const Color(0xFF8AA4D6),
    );
  }
  if (mode == 2) {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorSchemeSeed: const Color(0xFF8B5E34),
      scaffoldBackgroundColor: const Color(0xFFF4ECD8),
      canvasColor: const Color(0xFFF4ECD8),
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xFFF4ECD8), surfaceTintColor: Colors.transparent),
      navigationBarTheme: const NavigationBarThemeData(backgroundColor: Color(0xFFEADFC3)),
    );
  }
  return ThemeData(useMaterial3: true, brightness: Brightness.light, colorSchemeSeed: const Color(0xFF2F4A7D));
}

class KjvApp extends StatelessWidget {
  const KjvApp({super.key});

  @override
  Widget build(BuildContext context) {
    final phone = MediaQuery.platformBrightnessOf(context);
    return ValueListenableBuilder<int>(
      valueListenable: Prefs.theme,
      builder: (context, mode, _) => MaterialApp(
        title: 'KJV Bible',
        debugShowCheckedModeBanner: false,
        theme: _theme(mode, phone),
        home: const Boot(),
      ),
    );
  }
}

/// Copies the Bible to the phone the first time, then shows the app.
class Boot extends StatefulWidget {
  const Boot({super.key});

  @override
  State<Boot> createState() => _BootState();
}

class _BootState extends State<Boot> {
  BibleDb? _db;
  Object? _error;

  @override
  void initState() {
    super.initState();
    BibleDb.open().then((d) {
      if (mounted) setState(() => _db = d);
    }).catchError((Object e) {
      if (mounted) setState(() => _error = e);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_db != null) return HomeShell(db: _db!);
    return Scaffold(
      body: Center(
        child: _error != null
            ? Padding(padding: const EdgeInsets.all(24), child: Text('Could not open the Bible: $_error'))
            : const Column(
                mainAxisSize: MainAxisSize.min,
                children: [CircularProgressIndicator(), SizedBox(height: 16), Text('Opening the Bible…')],
              ),
      ),
    );
  }
}
