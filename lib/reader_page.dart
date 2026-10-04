import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'db.dart';
import 'prefs.dart';
import 'settings_sheet.dart';
import 'verse_text.dart';

/// Reads the Bible one chapter per page. Swipe sideways for the next or previous chapter.
class ReaderPage extends StatefulWidget {
  const ReaderPage({super.key, required this.db, required this.book, required this.chapter, this.verse});
  final BibleDb db;
  final int book;
  final int chapter;
  final int? verse;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  late final PageController _pages;
  late int _index;
  int? _flashVerse;
  final Set<int> _selected = {};

  @override
  void initState() {
    super.initState();
    _index = widget.db.indexOf(widget.book, widget.chapter);
    _pages = PageController(initialPage: _index);
    _flashVerse = widget.verse;
    _remember();
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _remember() {
    final (b, c) = widget.db.fromIndex(_index);
    Prefs.setLastRead(b, c);
  }

  (int, int) get _here => widget.db.fromIndex(_index);

  String _refLabel(int book, int chapter, List<int> verses) =>
      '${widget.db.book(book).name} $chapter:${verseRange(verses)}';

  List<Verse> get _selectedVerses {
    final (b, c) = _here;
    final nums = _selected.toList()..sort();
    return [for (final n in nums) widget.db.verse(b, c, n)].whereType<Verse>().toList();
  }

  String _formatted() {
    final (b, c) = _here;
    final vs = _selectedVerses;
    if (vs.isEmpty) return '';
    // group contiguous verses
    final groups = <List<Verse>>[];
    for (final v in vs) {
      if (groups.isNotEmpty && groups.last.last.verse + 1 == v.verse) {
        groups.last.add(v);
      } else {
        groups.add([v]);
      }
    }
    return groups
        .map((g) => '${g.map((v) => v.text).join(' ')}\n— ${_refLabel(b, c, g.map((v) => v.verse).toList())} (KJV)')
        .join('\n\n');
  }

  Future<void> _editNote() async {
    final (b, c) = _here;
    final first = _selectedVerses.first;
    final key = '$b.$c.${first.verse}';
    final controller = TextEditingController(text: Prefs.note(key));
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Note on ${_refLabel(b, c, [first.verse])}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 8,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Private. Stays on this phone.'),
        ),
        actions: [
          if (Prefs.note(key).isNotEmpty)
            TextButton(onPressed: () => Navigator.pop(ctx, ''), child: const Text('Delete')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Save')),
        ],
      ),
    );
    if (text != null) {
      await Prefs.setNote(key, text);
      if (mounted) setState(() => _selected.clear());
    }
  }

  Future<void> _highlightPicker() async {
    final (b, c) = _here;
    final keys = _selected.map((n) => '$b.$c.$n').toList();
    final choice = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (var i = 0; i < 4; i++)
                GestureDetector(
                  onTap: () => Navigator.pop(ctx, i),
                  child: CircleAvatar(radius: 24, backgroundColor: highlightColorsLight[i]),
                ),
              IconButton(
                tooltip: 'Remove highlight',
                icon: const Icon(Icons.format_color_reset),
                onPressed: () => Navigator.pop(ctx, -1),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null) return;
    await Prefs.setHighlight(keys, choice < 0 ? null : choice);
    if (mounted) setState(() => _selected.clear());
  }

  Future<void> _toggleFavorite() async {
    final (b, c) = _here;
    final keys = _selected.map((n) => '$b.$c.$n').toList();
    final allFav = keys.every(Prefs.isFavorite);
    await Prefs.setFavorites(keys, !allFav);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(allFav ? 'Removed from favorites' : 'Added to favorites')));
      setState(_selected.clear);
    }
  }

  Future<void> _chooseChapter() async {
    final b = widget.db.book(_here.$1);
    final picked = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (ctx, scroll) => Column(
          children: [
            Padding(padding: const EdgeInsets.all(16), child: Text(b.name, style: Theme.of(ctx).textTheme.titleMedium)),
            Expanded(
              child: GridView.count(
                controller: scroll,
                crossAxisCount: 6,
                padding: const EdgeInsets.all(12),
                children: [
                  for (var c = 1; c <= b.chapters; c++)
                    Padding(
                      padding: const EdgeInsets.all(4),
                      child: FilledButton.tonal(
                        style: FilledButton.styleFrom(padding: EdgeInsets.zero),
                        onPressed: () => Navigator.pop(ctx, c),
                        child: Text('$c'),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (picked != null) _pages.jumpToPage(widget.db.indexOf(b.id, picked));
  }

  @override
  Widget build(BuildContext context) {
    final (b, c) = _here;
    final book = widget.db.book(b);
    final hasSel = _selected.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: hasSel
            ? Text(_refLabel(b, c, (_selected.toList()..sort())))
            : TextButton(
                onPressed: _chooseChapter,
                child: Text('${book.name} $c', style: Theme.of(context).textTheme.titleLarge),
              ),
        leading: hasSel
            ? IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_selected.clear))
            : null,
        actions: [
          if (!hasSel)
            IconButton(
              tooltip: 'Text size and look',
              icon: const Icon(Icons.text_fields),
              onPressed: () => showSettingsSheet(context),
            ),
        ],
      ),
      body: PageView.builder(
        controller: _pages,
        itemCount: widget.db.totalChapters,
        onPageChanged: (i) => setState(() {
          _index = i;
          _selected.clear();
          _flashVerse = null;
          _remember();
        }),
        itemBuilder: (context, i) {
          final (pb, pc) = widget.db.fromIndex(i);
          return ChapterView(
            key: ValueKey(i),
            db: widget.db,
            book: pb,
            chapter: pc,
            flashVerse: i == _index ? _flashVerse : null,
            selected: i == _index ? _selected : const {},
            onTapVerse: (n) => setState(() {
              _flashVerse = null;
              if (!_selected.add(n)) _selected.remove(n);
            }),
            onPrev: i > 0 ? () => _pages.previousPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut) : null,
            onNext: i < widget.db.totalChapters - 1
                ? () => _pages.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut)
                : null,
          );
        },
      ),
      bottomNavigationBar: hasSel
          ? BottomAppBar(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  IconButton(
                    tooltip: 'Copy',
                    icon: const Icon(Icons.copy),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: _formatted()));
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
                        setState(_selected.clear);
                      }
                    },
                  ),
                  IconButton(
                    tooltip: 'Share or email',
                    icon: const Icon(Icons.share),
                    onPressed: () => Share.share(_formatted()),
                  ),
                  IconButton(tooltip: 'Highlight', icon: const Icon(Icons.format_color_fill), onPressed: _highlightPicker),
                  IconButton(tooltip: 'Add a note', icon: const Icon(Icons.edit_note), onPressed: _editNote),
                  IconButton(tooltip: 'Favorite', icon: const Icon(Icons.star_border), onPressed: _toggleFavorite),
                ],
              ),
            )
          : null,
    );
  }
}

/// One chapter. Each verse is its own line; tap to select.
class ChapterView extends StatefulWidget {
  const ChapterView({
    super.key,
    required this.db,
    required this.book,
    required this.chapter,
    required this.flashVerse,
    required this.selected,
    required this.onTapVerse,
    required this.onPrev,
    required this.onNext,
  });
  final BibleDb db;
  final int book;
  final int chapter;
  final int? flashVerse;
  final Set<int> selected;
  final void Function(int) onTapVerse;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  State<ChapterView> createState() => _ChapterViewState();
}

class _ChapterViewState extends State<ChapterView> {
  late final List<Verse> _verses = widget.db.chapter(widget.book, widget.chapter);
  late final String? _super = widget.db.superscription(widget.book, widget.chapter);
  final Map<int, GlobalKey> _keys = {};

  @override
  void initState() {
    super.initState();
    final f = widget.flashVerse;
    if (f != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _keys[f]?.currentContext;
        if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), alignment: 0.15);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        Prefs.fontScale,
        Prefs.lineHeight,
        Prefs.serif,
        Prefs.redLetters,
        Prefs.showItalics,
        Prefs.libraryChanged,
      ]),
      builder: (context, _) {
        final base = readingStyle(context);
        final theme = Theme.of(context);
        final red = Prefs.redLetters.value;
        final redColor = redLetterColor(context);
        final book = widget.db.book(widget.book);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                '${book.name} ${widget.chapter}',
                style: theme.textTheme.headlineSmall?.copyWith(fontFamily: Prefs.serif.value ? 'serif' : null),
              ),
            ),
            if (_super != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_super, style: base.copyWith(fontStyle: FontStyle.italic, color: theme.colorScheme.onSurfaceVariant)),
              ),
            for (final v in _verses) _verseTile(context, v, base, red, redColor),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(onPressed: widget.onPrev, icon: const Icon(Icons.chevron_left), label: const Text('Previous')),
                TextButton.icon(
                  onPressed: widget.onNext,
                  icon: const Icon(Icons.chevron_right),
                  label: const Text('Next'),
                  iconAlignment: IconAlignment.end,
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _verseTile(BuildContext context, Verse v, TextStyle base, bool red, Color redColor) {
    final theme = Theme.of(context);
    final key = v.key;
    final hl = Prefs.highlight(key);
    final selected = widget.selected.contains(v.verse);
    final flash = widget.flashVerse == v.verse;
    final hasNote = Prefs.note(key).isNotEmpty;
    final fav = Prefs.isFavorite(key);
    Color? bg;
    if (selected || flash) {
      bg = theme.colorScheme.primary.withValues(alpha: 0.18);
    } else if (hl != null) {
      bg = highlightColor(context, hl);
    }
    final numStyle = base.copyWith(
      fontSize: base.fontSize! * 0.62,
      fontWeight: FontWeight.w700,
      color: theme.colorScheme.primary,
      height: 1.0,
    );
    return Container(
      key: _keys.putIfAbsent(v.verse, () => GlobalKey()),
      margin: const EdgeInsets.symmetric(vertical: 1),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => widget.onTapVerse(v.verse),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '${v.verse} ', style: numStyle),
                ...markupSpans(v.markup, base: base, italics: Prefs.showItalics.value, red: red, redColor: redColor),
                if (hasNote) TextSpan(text: '  ✎', style: base.copyWith(fontSize: base.fontSize! * 0.8, color: theme.colorScheme.tertiary)),
                if (fav) TextSpan(text: '  ★', style: base.copyWith(fontSize: base.fontSize! * 0.8, color: theme.colorScheme.tertiary)),
              ],
              style: base,
            ),
          ),
        ),
      ),
    );
  }
}
