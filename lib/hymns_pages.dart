import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'db.dart';
import 'prefs.dart';
import 'settings_sheet.dart';
import 'verse_text.dart';

void openHymn(BuildContext context, Hymn h) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => HymnPage(hymn: h)));
}

/// A to Z list of the hymns, with search.
class HymnsTab extends StatefulWidget {
  const HymnsTab({super.key, required this.db});
  final BibleDb db;

  @override
  State<HymnsTab> createState() => _HymnsTabState();
}

class _HymnsTabState extends State<HymnsTab> {
  final _ctl = TextEditingController();
  late final List<Hymn> _all = widget.db.allHymns();
  List<Hymn> _shown = const [];
  String _q = '';

  @override
  void initState() {
    super.initState();
    _shown = _all;
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _run(String q) {
    q = q.trim();
    setState(() {
      _q = q;
      _shown = q.isEmpty ? _all : widget.db.searchHymns(q);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ctl,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search ${_all.length} hymns by title or words',
            border: InputBorder.none,
            suffixIcon: _ctl.text.isEmpty
                ? null
                : IconButton(icon: const Icon(Icons.clear), onPressed: () { _ctl.clear(); _run(''); }),
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: _run,
        ),
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: () => _run(_ctl.text)),
          IconButton(icon: const Icon(Icons.text_fields), tooltip: 'Reading settings', onPressed: () => showSettingsSheet(context)),
        ],
      ),
      body: _shown.isEmpty
          ? const Center(child: Text('No hymns found'))
          : ListView.builder(
              itemCount: _shown.length + (_q.isEmpty ? 1 : 0),
              itemBuilder: (c, i) {
                if (_q.isEmpty && i == _shown.length) {
                  return const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'Public-domain hymns (first published 1929 or earlier), from the WorshipCommons library.',
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                final h = _shown[i];
                return ListTile(
                  title: Text(h.title),
                  subtitle: Text([h.writer, if (h.year != null) '${h.year}'].where((s) => s.isNotEmpty).join(' · '),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Prefs.isHymnFavorite(h.n) ? const Icon(Icons.star, size: 18) : null,
                  onTap: () => openHymn(c, h),
                );
              },
            ),
    );
  }
}

/// One hymn, using the same text size, font and theme as the Bible.
class HymnPage extends StatelessWidget {
  const HymnPage({super.key, required this.hymn});
  final Hymn hymn;

  String get _plain {
    final by = [hymn.writer, if (hymn.year != null) '${hymn.year}'].where((s) => s.isNotEmpty).join(', ');
    return '${hymn.title}\n${by.isEmpty ? '' : '$by\n'}\n${hymn.lyrics}';
  }

  @override
  Widget build(BuildContext context) {
    final stanzas = hymn.lyrics.split(RegExp(r'\n\s*\n'));
    return Scaffold(
      appBar: AppBar(
        title: Text(hymn.title, overflow: TextOverflow.ellipsis),
        actions: [
          ValueListenableBuilder<int>(
            valueListenable: Prefs.libraryChanged,
            builder: (context, _, __) => IconButton(
              icon: Icon(Prefs.isHymnFavorite(hymn.n) ? Icons.star : Icons.star_border),
              tooltip: 'Favorite',
              onPressed: () => Prefs.toggleHymnFavorite(hymn.n),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _plain));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
            },
          ),
          IconButton(icon: const Icon(Icons.ios_share), tooltip: 'Share', onPressed: () => Share.share(_plain)),
          IconButton(icon: const Icon(Icons.text_fields), tooltip: 'Reading settings', onPressed: () => showSettingsSheet(context)),
        ],
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([Prefs.fontScale, Prefs.lineHeight, Prefs.serif]),
        builder: (context, _) {
          final style = readingStyle(context);
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            children: [
              Text(hymn.title, style: style.copyWith(fontSize: style.fontSize! * 1.25, fontWeight: FontWeight.bold)),
              if (hymn.writer.isNotEmpty || hymn.year != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    [hymn.writer, if (hymn.year != null) '${hymn.year}'].where((s) => s.isNotEmpty).join(' · '),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              const SizedBox(height: 16),
              for (final st in stanzas) _stanza(context, st, style),
            ],
          );
        },
      ),
    );
  }

  Widget _stanza(BuildContext context, String st, TextStyle style) {
    final lines = st.trim().split('\n');
    var label = '';
    if (lines.isNotEmpty && RegExp(r'^(Verse \d+|Chorus|Refrain|Bridge|Tag|Intro|Outro|Pre-?Chorus)\b', caseSensitive: false).hasMatch(lines.first.trim()) && lines.first.trim().length < 20) {
      label = lines.removeAt(0).trim();
    }
    final isChorus = RegExp(r'chorus|refrain', caseSensitive: false).hasMatch(label);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (label.isNotEmpty)
          Text(label.toUpperCase(), style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1, color: Theme.of(context).colorScheme.primary)),
        Padding(
          padding: EdgeInsets.only(left: isChorus ? 18 : 0, top: 2),
          child: Text(lines.join('\n'), style: style.copyWith(fontStyle: isChorus ? FontStyle.italic : null)),
        ),
      ]),
    );
  }
}
