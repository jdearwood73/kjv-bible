import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

const _assetPath = 'assets/db/kjv.sqlite';
const _dbVersion = 2; // bump when assets/db/kjv.sqlite changes

class Book {
  Book(this.id, this.name, this.abbrev, this.testament, this.chapters);
  final int id;
  final String name;
  final String abbrev;
  final String testament;
  final int chapters;
}

class Verse {
  Verse(this.id, this.book, this.chapter, this.verse, this.text, this.markup);
  final int id;
  final int book;
  final int chapter;
  final int verse;
  final String text;
  final String markup;
  String get key => '$book.$chapter.$verse';
}

class SearchHit {
  SearchHit(this.verse, this.snippet);
  final Verse verse;
  final String snippet; // «matched» words are wrapped in « »
}

class Hymn {
  Hymn(this.n, this.title, this.writer, this.year, this.themes, this.scripture, this.lyrics);
  final int n;
  final String title;
  final String writer;
  final int? year;
  final String themes;
  final String scripture;
  final String lyrics; // blank-line separated stanzas; first line of a stanza may be "Verse 1" / "Chorus"
}

class Ref {
  Ref(this.book, this.chapter, this.verse, this.endVerse);
  final Book book;
  final int chapter;
  final int? verse;
  final int? endVerse;
}

class BibleDb {
  BibleDb._(this._db) {
    books = [
      for (final r in _db.select('SELECT id, name, abbrev, testament, chapters FROM books ORDER BY id'))
        Book(r['id'] as int, r['name'] as String, r['abbrev'] as String, r['testament'] as String, r['chapters'] as int),
    ];
    var n = 0;
    _firstIndex = {};
    for (final b in books) {
      _firstIndex[b.id] = n;
      n += b.chapters;
    }
    totalChapters = n;
  }

  final Database _db;
  late final List<Book> books;
  late final Map<int, int> _firstIndex;
  late final int totalChapters;

  /// Copies the bundled database to the phone the first time (and after an update).
  static Future<BibleDb> open({void Function(double)? onProgress}) async {
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, 'kjv.sqlite'));
    final prefs = await SharedPreferences.getInstance();
    if (!file.existsSync() || (prefs.getInt('dbVersion') ?? 0) != _dbVersion) {
      onProgress?.call(0.1);
      final data = await rootBundle.load(_assetPath);
      onProgress?.call(0.6);
      await file.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
      await prefs.setInt('dbVersion', _dbVersion);
      onProgress?.call(1.0);
    }
    return BibleDb._(sqlite3.open(file.path, mode: OpenMode.readOnly));
  }

  Book book(int id) => books[id - 1];

  /// Chapters are numbered 0..1188 across the whole Bible so a page view can swipe through them.
  int indexOf(int book, int chapter) => _firstIndex[book]! + chapter - 1;

  (int, int) fromIndex(int index) {
    for (final b in books.reversed) {
      final first = _firstIndex[b.id]!;
      if (index >= first) return (b.id, index - first + 1);
    }
    return (1, 1);
  }

  Verse _verse(Row r) => Verse(
        r['id'] as int,
        r['book'] as int,
        r['chapter'] as int,
        r['verse'] as int,
        r['text'] as String,
        r['markup'] as String,
      );

  List<Verse> chapter(int book, int chapter) => [
        for (final r in _db.select(
          'SELECT * FROM verses WHERE book = ? AND chapter = ? ORDER BY verse',
          [book, chapter],
        ))
          _verse(r),
      ];

  String? superscription(int book, int chapter) {
    final rs = _db.select('SELECT text FROM superscriptions WHERE book = ? AND chapter = ?', [book, chapter]);
    return rs.isEmpty ? null : rs.first['text'] as String;
  }

  Verse? verse(int book, int chapter, int verse) {
    final rs = _db.select(
      'SELECT * FROM verses WHERE book = ? AND chapter = ? AND verse = ?',
      [book, chapter, verse],
    );
    return rs.isEmpty ? null : _verse(rs.first);
  }

  Verse? byKey(String key) {
    final p = key.split('.');
    if (p.length != 3) return null;
    return verse(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }

  /// A verse for today, the same all day. Picks a mid-length verse (skips genealogies and one-liners).
  Verse dailyVerse(DateTime day) {
    final seed = day.year * 1000 + day.month * 40 + day.day;
    final rs = _db.select(
      "SELECT * FROM verses WHERE length(text) BETWEEN 90 AND 230 AND text NOT LIKE '%begat%' "
      "AND text NOT LIKE '%Selah%' ORDER BY id LIMIT 1 OFFSET ?",
      [(seed * 7919) % 15000],
    );
    return _verse(rs.isNotEmpty ? rs.first : _db.select('SELECT * FROM verses WHERE id = 26137').first); // John 3:16 fallback
  }

  // ------------------------------------------------------------ hymns

  Hymn _hymn(Row r) => Hymn(
        r['n'] as int,
        r['title'] as String,
        (r['writer'] as String?) ?? '',
        r['year'] as int?,
        (r['themes'] as String?) ?? '',
        (r['scripture'] as String?) ?? '',
        (r['lyrics'] as String?) ?? '',
      );

  /// Every hymn, A to Z (lyrics included; there are only about 500).
  List<Hymn> allHymns() => [for (final r in _db.select('SELECT * FROM hymns ORDER BY title COLLATE NOCASE')) _hymn(r)];

  Hymn? hymn(int n) {
    final rs = _db.select('SELECT * FROM hymns WHERE n = ?', [n]);
    return rs.isEmpty ? null : _hymn(rs.first);
  }

  /// Searches hymn titles and words. Same syntax as Bible search ("phrase", word*, a w/5 b).
  List<Hymn> searchHymns(String input, {int limit = 100}) {
    final q = ftsQuery(input);
    if (q.isEmpty) return const [];
    try {
      final rs = _db.select(
        'SELECT h.* FROM hymns_fts JOIN hymns h ON h.n = hymns_fts.rowid WHERE hymns_fts MATCH ? ORDER BY bm25(hymns_fts, 8.0, 1.0) LIMIT ?',
        [q, limit],
      );
      return [for (final r in rs) _hymn(r)];
    } on SqliteException {
      return const [];
    }
  }

  // ------------------------------------------------------------ search

  static final RegExp _qTok = RegExp(
    r'"([^"]*)"|\b(?:w|near)/(\d+)\b|(?<!\w)/(\d+)\b|\b(OR)\b|([A-Za-z0-9]+)',
    caseSensitive: false,
  );

  /// words: all of them. "exact phrase". a w/5 b : within 5 words. a OR b : either.
  static String ftsQuery(String input) {
    final endsWithQuote = input.trimRight().endsWith('"');
    final items = <List<Object>>[];
    for (final m in _qTok.allMatches(input)) {
      if (m.group(1) != null) {
        final ws = RegExp(r"[a-z0-9]+").allMatches(m.group(1)!.toLowerCase()).map((x) => x.group(0)!).toList();
        if (ws.isNotEmpty) items.add(['p', ws]);
      } else if (m.group(2) != null || m.group(3) != null) {
        items.add(['near', int.parse(m.group(2) ?? m.group(3)!)]);
      } else if (m.group(4) != null) {
        items.add(['or']);
      } else {
        items.add([
          'p',
          [m.group(5)!.toLowerCase()],
        ]);
      }
    }
    final grouped = <List<Object>>[];
    var i = 0;
    while (i < items.length) {
      final it = items[i];
      if (it[0] == 'near') {
        if (grouped.isNotEmpty &&
            (grouped.last[0] == 'p' || grouped.last[0] == 'n') &&
            i + 1 < items.length &&
            items[i + 1][0] == 'p') {
          final prev = grouped.removeLast();
          final next = items[i + 1][1] as List<String>;
          final n = it[1] as int;
          if (prev[0] == 'p') {
            grouped.add(['n', <List<String>>[prev[1] as List<String>, next], n]);
          } else {
            final phrases = [...(prev[1] as List<List<String>>), next];
            final pn = prev[2] as int;
            grouped.add(['n', phrases, n > pn ? n : pn]);
          }
          i += 2;
          continue;
        }
        i++;
        continue;
      }
      grouped.add(it);
      i++;
    }
    final parts = <String>[];
    for (var k = 0; k < grouped.length; k++) {
      final it = grouped[k];
      final last = k == grouped.length - 1;
      if (it[0] == 'or') {
        if (parts.isNotEmpty && !last) parts.add('OR');
      } else if (it[0] == 'p') {
        final ws = it[1] as List<String>;
        if (ws.length == 1) {
          parts.add('"${ws[0]}"${last && !endsWithQuote ? '*' : ''}');
        } else {
          parts.add('"${ws.join(' ')}"');
        }
      } else {
        final phrases = (it[1] as List<List<String>>).map((p) => '"${p.join(' ')}"').join(' ');
        parts.add('NEAR($phrases, ${it[2]})');
      }
    }
    while (parts.isNotEmpty && parts.last == 'OR') {
      parts.removeLast();
    }
    return parts.join(' ');
  }

  static List<String> _terms(String input) => input
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((t) => t.length > 1 && t != 'or' && t != 'near')
      .toList();

  /// [testament] "OT" or "NT"; [bookId] limits to one book.
  List<SearchHit> search(String input, {int limit = 150, String? testament, int? bookId}) {
    final q = ftsQuery(input);
    if (q.isEmpty) return const [];
    final where = StringBuffer('verses_fts MATCH ?');
    final args = <Object>[q];
    if (bookId != null) {
      where.write(' AND v.book = ?');
      args.add(bookId);
    } else if (testament == 'OT') {
      where.write(' AND v.book <= 39');
    } else if (testament == 'NT') {
      where.write(' AND v.book >= 40');
    }
    args.add(limit * 2);
    List<SearchHit> hits;
    try {
      final rs = _db.select(
        '''
        SELECT v.*, snippet(verses_fts, 0, '«', '»', '…', 40) AS snip
        FROM verses_fts JOIN verses v ON v.id = verses_fts.rowid
        WHERE $where
        ORDER BY bm25(verses_fts)
        LIMIT ?
        ''',
        args,
      );
      hits = [for (final r in rs) SearchHit(_verse(r), r['snip'] as String)];
    } on SqliteException {
      return const [];
    }
    // exact words typed first (the index also matches word endings)
    final terms = _terms(input);
    int score(SearchHit h) {
      final marked = RegExp('«([^»]*)»').allMatches(h.snippet).map((m) => m.group(1)!.toLowerCase()).toList();
      var s = 0;
      for (final t in terms) {
        if (marked.contains(t)) s += 2;
      }
      return s;
    }

    final idx = {for (var i = 0; i < hits.length; i++) hits[i]: i};
    hits.sort((a, b) {
      final sa = score(a), sb = score(b);
      return sa != sb ? sb.compareTo(sa) : idx[a]!.compareTo(idx[b]!);
    });
    return hits.take(limit).toList();
  }

  // ------------------------------------------------------------ references like "John 3:16" or "1 cor 13"

  static const _aliases = <String, String>{
    'ps': 'psalms', 'psalm': 'psalms', 'psa': 'psalms', 'pss': 'psalms',
    'song': 'songofsolomon', 'sos': 'songofsolomon', 'songofsongs': 'songofsolomon', 'canticles': 'songofsolomon',
    'jn': 'john', 'mt': 'matthew', 'mk': 'mark', 'lk': 'luke', 'rev': 'revelation', 'revelations': 'revelation',
    'ex': 'exodus', 'gn': 'genesis', 'dt': 'deuteronomy', 'jas': 'james', 'phil': 'philippians', 'php': 'philippians',
    'phm': 'philemon', 'philem': 'philemon', 'heb': 'hebrews', 'eccl': 'ecclesiastes', 'eccles': 'ecclesiastes',
  };

  Ref? parseRef(String input) {
    final s = input.toLowerCase().replaceAll('.', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    final m = RegExp(r'^(\d\s?)?([a-z]+(?: of [a-z]+)?)\s*(\d+)?(?:\s*[: ]\s*(\d+)(?:\s*[-–]\s*(\d+))?)?$').firstMatch(s);
    if (m == null) return null;
    final prefix = (m.group(1) ?? '').trim();
    var name = '$prefix${(m.group(2) ?? '').replaceAll(' ', '')}';
    name = _aliases[name] ?? name;
    if (name.length < 2) return null;
    Book? found;
    for (final b in books) {
      final full = b.name.toLowerCase().replaceAll(' ', '');
      if (full == name || b.abbrev.toLowerCase() == name) {
        found = b;
        break;
      }
    }
    found ??= () {
      for (final b in books) {
        if (b.name.toLowerCase().replaceAll(' ', '').startsWith(name)) return b;
      }
      return null;
    }();
    if (found == null) return null;
    final ch = int.tryParse(m.group(3) ?? '') ?? 1;
    if (ch < 1 || ch > found.chapters) return null;
    final v = int.tryParse(m.group(4) ?? '');
    final e = int.tryParse(m.group(5) ?? '');
    return Ref(found, ch, v, e);
  }
}
