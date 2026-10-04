import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reading settings, favorites, highlights, notes and reading position. Everything stays on the phone.
class Prefs {
  static late SharedPreferences _p;

  // reading settings
  static final ValueNotifier<double> fontScale = ValueNotifier(1.0);
  static final ValueNotifier<double> lineHeight = ValueNotifier(1.6);
  static final ValueNotifier<bool> serif = ValueNotifier(true);
  static final ValueNotifier<int> theme = ValueNotifier(0); // 0 phone, 1 light, 2 sepia, 3 dark
  static final ValueNotifier<bool> redLetters = ValueNotifier(false);
  static final ValueNotifier<bool> showItalics = ValueNotifier(true);

  // library
  static final ValueNotifier<int> libraryChanged = ValueNotifier(0);
  static List<String> _favs = [];
  static Map<String, int> _highlights = {};
  static Map<String, String> _notes = {};
  static List<int> _hymnFavs = [];

  static Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    fontScale.value = (_p.getDouble('fontScale') ?? 1.0).clamp(0.7, 2.2);
    lineHeight.value = (_p.getDouble('lineHeight') ?? 1.6).clamp(1.2, 2.2);
    serif.value = _p.getBool('serif') ?? true;
    theme.value = (_p.getInt('theme') ?? 0).clamp(0, 3);
    redLetters.value = _p.getBool('redLetters') ?? false;
    showItalics.value = _p.getBool('showItalics') ?? true;
    _hymnFavs = [for (final s in _p.getStringList('hymnFavs') ?? const <String>[]) int.parse(s)];
    _favs = List<String>.from(_p.getStringList('favs') ?? const <String>[]);
    try {
      _highlights = Map<String, int>.from(jsonDecode(_p.getString('highlights') ?? '{}') as Map);
      _notes = Map<String, String>.from(jsonDecode(_p.getString('notes') ?? '{}') as Map);
    } catch (_) {
      _highlights = {};
      _notes = {};
    }
  }

  static Future<void> setFontScale(double v) async {
    fontScale.value = v;
    await _p.setDouble('fontScale', v);
  }

  static Future<void> setLineHeight(double v) async {
    lineHeight.value = v;
    await _p.setDouble('lineHeight', v);
  }

  static Future<void> setSerif(bool v) async {
    serif.value = v;
    await _p.setBool('serif', v);
  }

  static Future<void> setTheme(int v) async {
    theme.value = v;
    await _p.setInt('theme', v);
  }

  static Future<void> setRedLetters(bool v) async {
    redLetters.value = v;
    await _p.setBool('redLetters', v);
  }

  static Future<void> setShowItalics(bool v) async {
    showItalics.value = v;
    await _p.setBool('showItalics', v);
  }

  // ---- reading position
  static ({int book, int chapter})? get lastRead {
    final s = _p.getString('lastRead');
    if (s == null) return null;
    final parts = s.split('.');
    if (parts.length != 2) return null;
    return (book: int.parse(parts[0]), chapter: int.parse(parts[1]));
  }

  static Future<void> setLastRead(int book, int chapter) => _p.setString('lastRead', '$book.$chapter');

  // ---- favorites (verse keys "book.chapter.verse")
  static List<String> get favorites => List.unmodifiable(_favs);
  static bool isFavorite(String key) => _favs.contains(key);

  static Future<void> setFavorites(Iterable<String> keys, bool on) async {
    for (final k in keys) {
      _favs.remove(k);
      if (on) _favs.insert(0, k);
    }
    await _p.setStringList('favs', _favs);
    libraryChanged.value++;
  }

  // ---- favorite hymns (hymn numbers)
  static List<int> get hymnFavorites => List.unmodifiable(_hymnFavs);
  static bool isHymnFavorite(int n) => _hymnFavs.contains(n);

  static Future<void> toggleHymnFavorite(int n) async {
    if (!_hymnFavs.remove(n)) _hymnFavs.insert(0, n);
    await _p.setStringList('hymnFavs', [for (final h in _hymnFavs) '$h']);
    libraryChanged.value++;
  }

  // ---- highlights (color index 0..3)
  static Map<String, int> get highlights => Map.unmodifiable(_highlights);
  static int? highlight(String key) => _highlights[key];

  static Future<void> setHighlight(Iterable<String> keys, int? color) async {
    for (final k in keys) {
      if (color == null) {
        _highlights.remove(k);
      } else {
        _highlights[k] = color;
      }
    }
    await _p.setString('highlights', jsonEncode(_highlights));
    libraryChanged.value++;
  }

  // ---- notes
  static Map<String, String> get notes => Map.unmodifiable(_notes);
  static String note(String key) => _notes[key] ?? '';

  static Future<void> setNote(String key, String text) async {
    final t = text.trim();
    if (t.isEmpty) {
      _notes.remove(key);
    } else {
      _notes[key] = t;
    }
    await _p.setString('notes', jsonEncode(_notes));
    libraryChanged.value++;
  }
}
