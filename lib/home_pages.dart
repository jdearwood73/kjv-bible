import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'db.dart';
import 'prefs.dart';
import 'reader_page.dart';
import 'settings_sheet.dart';
import 'verse_text.dart';

void openReader(BuildContext context, BibleDb db, int book, int chapter, [int? verse]) {
  Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => ReaderPage(db: db, book: book, chapter: chapter, verse: verse),
  ));
}

String verseLabel(BibleDb db, Verse v) => '${db.books[v.book - 1].name} ${v.chapter}:${v.verse}';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.db});
  final BibleDb db;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      ReadTab(db: widget.db),
      SearchTab(db: widget.db),
      LibraryTab(db: widget.db),
    ];
    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: 'Read'),
          NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
          NavigationDestination(icon: Icon(Icons.bookmarks_outlined), selectedIcon: Icon(Icons.bookmarks), label: 'Library'),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Read

class ReadTab extends StatelessWidget {
  const ReadTab({super.key, required this.db});
  final BibleDb db;

  @override
  Widget build(BuildContext context) {
    final ot = db.books.where((b) => b.testament == 'OT').toList();
    final nt = db.books.where((b) => b.testament != 'OT').toList();
    final last = Prefs.lastRead;
    final daily = db.dailyVerse(DateTime.now());
    return Scaffold(
      appBar: AppBar(
        title: const Text('King James Bible'),
        actions: [
          IconButton(icon: const Icon(Icons.text_fields), tooltip: 'Reading settings', onPressed: () => showSettingsSheet(context)),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'About',
            onPressed: () => showAboutDialog(
              context: context,
              applicationName: 'KJV Bible',
              children: const [
                Text('The Authorized (King James) Version, 1769 Cambridge text, public domain in the United States. '
                    'Source: eBible.org. Everything stays on your phone; the app never goes online.'),
              ],
            ),
          ),
        ],
      ),
      body: ListView(
        children: [
          if (last != null)
            ListTile(
              leading: const Icon(Icons.play_circle_outline),
              title: const Text('Continue reading'),
              subtitle: Text('${db.books[last.book - 1].name} ${last.chapter}'),
              onTap: () => openReader(context, db, last.book, last.chapter),
            ),
          Card(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: InkWell(
              onTap: () => openReader(context, db, daily.book, daily.chapter, daily.verse),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Verse of the day', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 6),
                  Text(daily.text, style: readingStyle(context).copyWith(fontSize: 17)),
                  const SizedBox(height: 6),
                  Text(verseLabel(db, daily), style: const TextStyle(fontWeight: FontWeight.bold)),
                ]),
              ),
            ),
          ),
          _header(context, 'Old Testament'),
          for (final b in ot) _bookTile(context, b),
          _header(context, 'New Testament'),
          for (final b in nt) _bookTile(context, b),
        ],
      ),
    );
  }

  Widget _header(BuildContext c, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(t, style: Theme.of(c).textTheme.titleSmall?.copyWith(color: Theme.of(c).colorScheme.primary)),
      );

  Widget _bookTile(BuildContext c, Book b) => ListTile(
        title: Text(b.name),
        trailing: Text('${b.chapters}', style: Theme.of(c).textTheme.bodySmall),
        onTap: () => Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => ChaptersPage(db: db, book: b))),
      );
}

class ChaptersPage extends StatelessWidget {
  const ChaptersPage({super.key, required this.db, required this.book});
  final BibleDb db;
  final Book book;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(book.name)),
      body: GridView.count(
        crossAxisCount: 5,
        padding: const EdgeInsets.all(12),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        children: [
          for (var c = 1; c <= book.chapters; c++)
            FilledButton.tonal(
              style: FilledButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: () => openReader(context, db, book.id, c),
              child: Text('$c'),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Search

class SearchTab extends StatefulWidget {
  const SearchTab({super.key, required this.db});
  final BibleDb db;

  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  final _ctl = TextEditingController();
  String _scope = 'all'; // all, OT, NT
  List<SearchHit> _hits = [];
  Ref? _ref;
  String _query = '';
  bool _searched = false;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _run(String q) {
    q = q.trim();
    setState(() {
      _query = q;
      _searched = q.isNotEmpty;
      _ref = q.isEmpty ? null : widget.db.parseRef(q);
      if (q.isEmpty) {
        _hits = [];
        return;
      }
      try {
        _hits = widget.db.search(q, testament: _scope == 'all' ? null : _scope);
      } catch (_) {
        _hits = [];
      }
    });
  }

  List<InlineSpan> _snippet(String s, TextStyle base) {
    final out = <InlineSpan>[];
    for (final m in RegExp(r'«([^»]*)»|([^«]+)').allMatches(s)) {
      if (m.group(1) != null) {
        out.add(TextSpan(text: m.group(1), style: base.copyWith(fontWeight: FontWeight.bold, backgroundColor: const Color(0x55FFC107))));
      } else {
        out.add(TextSpan(text: m.group(2), style: base));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final db = widget.db;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ctl,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Word, "exact phrase", or John 3:16',
            border: InputBorder.none,
            suffixIcon: _ctl.text.isEmpty
                ? null
                : IconButton(icon: const Icon(Icons.clear), onPressed: () { _ctl.clear(); _run(''); }),
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: _run,
        ),
        actions: [IconButton(icon: const Icon(Icons.search), onPressed: () => _run(_ctl.text))],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'all', label: Text('Whole Bible')),
              ButtonSegment(value: 'OT', label: Text('Old')),
              ButtonSegment(value: 'NT', label: Text('New')),
            ],
            selected: {_scope},
            onSelectionChanged: (s) {
              _scope = s.first;
              _run(_ctl.text);
            },
          ),
        ),
        if (_ref != null)
          ListTile(
            leading: const Icon(Icons.arrow_forward),
            title: Text('Go to ${_ref!.book.name} ${_ref!.chapter}${_ref!.verse != null ? ':${_ref!.verse}' : ''}'
                '${_ref!.endVerse != null ? '-${_ref!.endVerse}' : ''}'),
            onTap: () => openReader(context, db, _ref!.book.id, _ref!.chapter, _ref!.verse),
          ),
        Expanded(
          child: !_searched
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Search words ("love one another"), phrases in quotes, a word with * at the end (righteous*), '
                      'or jump straight to a passage (Ps 23, 1 Cor 13).',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : _hits.isEmpty
                  ? const Center(child: Text('No verses found'))
                  : ListView.separated(
                      itemCount: _hits.length + 1,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (c, i) {
                        if (i == 0) {
                          return Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text('${_hits.length}${_hits.length >= 150 ? '+' : ''} verses', style: Theme.of(c).textTheme.labelLarge),
                          );
                        }
                        final h = _hits[i - 1];
                        final base = DefaultTextStyle.of(c).style.copyWith(fontSize: 16);
                        return ListTile(
                          title: Text(verseLabel(db, h.verse), style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text.rich(TextSpan(children: _snippet(h.snippet, base))),
                          onTap: () => openReader(c, db, h.verse.book, h.verse.chapter, h.verse.verse),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- Library

class LibraryTab extends StatelessWidget {
  const LibraryTab({super.key, required this.db});
  final BibleDb db;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My library'),
          bottom: const TabBar(tabs: [Tab(text: 'Favorites'), Tab(text: 'Highlights'), Tab(text: 'Notes')]),
        ),
        body: ValueListenableBuilder<int>(
          valueListenable: Prefs.libraryChanged,
          builder: (context, _, __) => TabBarView(children: [
            _list(context, 'favorites', Prefs.favorites),
            _list(context, 'highlights', Prefs.highlights.keys.toList().reversed.toList()),
            _list(context, 'notes', Prefs.notes.keys.toList().reversed.toList()),
          ]),
        ),
      ),
    );
  }

  Widget _list(BuildContext context, String what, List<String> keys) {
    final verses = <Verse>[for (final k in keys) if (db.byKey(k) != null) db.byKey(k)!];
    if (verses.isEmpty) {
      return Center(child: Text('No $what yet.\nTap a verse in the reader to add one.', textAlign: TextAlign.center));
    }
    return Column(children: [
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          icon: const Icon(Icons.ios_share, size: 18),
          label: const Text('Share all'),
          onPressed: () => Share.share(_export(verses, what)),
        ),
      ),
      Expanded(
        child: ListView.separated(
          itemCount: verses.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (c, i) {
            final v = verses[i];
            final note = Prefs.note(v.key);
            final hl = Prefs.highlight(v.key);
            return ListTile(
              tileColor: hl != null && what == 'highlights' ? highlightColor(c, hl).withOpacity(0.5) : null,
              title: Text(verseLabel(db, v), style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(note.isNotEmpty && what == 'notes' ? '${v.text}\n✎ $note' : v.text),
              onTap: () => openReader(c, db, v.book, v.chapter, v.verse),
            );
          },
        ),
      ),
    ]);
  }

  String _export(List<Verse> verses, String what) {
    final b = StringBuffer();
    for (final v in verses) {
      b.writeln('${verseLabel(db, v)} (KJV)');
      b.writeln(v.text);
      final n = Prefs.note(v.key);
      if (n.isNotEmpty) b.writeln('Note: $n');
      b.writeln();
    }
    return b.toString().trim();
  }
}
