import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'db.dart';

/// An old book that ships inside the app as a scanned PDF.
class ScanBook {
  const ScanBook({required this.id, required this.title, required this.subtitle, required this.asset, required this.credit, required this.version});
  final String id;
  final String title;
  final String subtitle;
  final String asset;
  final String credit;
  final int version; // bump when the bundled PDF changes
}

const hymnal1883 = ScanBook(
  id: 'hymnal1883',
  title: 'Baptist Hymnal (1883)',
  subtitle: 'American Baptist Publication Society, Philadelphia · 262 pages',
  asset: 'assets/pdf/baptist_hymnal_1883.pdf',
  credit: 'Page scans digitized by the Library of Congress.',
  version: 1,
);

const kjv1611 = ScanBook(
  id: 'kjv1611',
  title: 'King James Bible, 1611 edition',
  subtitle: 'Reprint of the original 1611 edition · 1,460 pages',
  asset: 'assets/pdf/kjv_1611.pdf',
  credit: 'Reprint of the 1611 edition of the Authorized Version. Page numbers shown are PDF pages.',
  version: 1,
);

const allScans = [hymnal1883, kjv1611];

/// Copies a bundled PDF to the phone once so it can be opened from a file (uses little memory afterwards).
Future<String> preparePdf(ScanBook b) async {
  final dir = await getApplicationSupportDirectory();
  final file = File(p.join(dir.path, '${b.id}_v${b.version}.pdf'));
  if (await file.exists() && await file.length() > 1000000) return file.path;
  final data = await rootBundle.load(b.asset);
  final tmp = File('${file.path}.part');
  await tmp.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
  await tmp.rename(file.path);
  return file.path;
}

void openScan(BuildContext context, ScanBook b, {int? page, List<(String, int)> outline = const []}) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ScanPage(book: b, page: page, outline: outline)));
}

class ScanPage extends StatefulWidget {
  const ScanPage({super.key, required this.book, this.page, this.outline = const []});
  final ScanBook book;
  final int? page; // PDF page to open at (1-based); null resumes where you left off
  final List<(String, int)> outline;

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final _controller = PdfViewerController();
  String? _path;
  Object? _error;
  int _current = 1;
  int _count = 0;
  int _start = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _start = widget.page ?? prefs.getInt('scan_${widget.book.id}') ?? 1;
      _current = _start;
      final path = await preparePdf(widget.book);
      if (mounted) setState(() => _path = path);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _remember(int n) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('scan_${widget.book.id}', n);
  }

  void _goTo(int n) {
    final c = _count == 0 ? n : n.clamp(1, _count);
    _controller.goToPage(pageNumber: c);
  }

  Future<void> _askPage() async {
    final ctl = TextEditingController(text: '$_current');
    final n = await showDialog<int>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Go to page${_count > 0 ? ' (1–$_count)' : ''}'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.number,
          onSubmitted: (v) => Navigator.pop(c, int.tryParse(v)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, int.tryParse(ctl.text)), child: const Text('Go')),
        ],
      ),
    );
    if (n != null) _goTo(n);
  }

  void _showContents() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (c, scroll) => ListView.builder(
          controller: scroll,
          itemCount: widget.outline.length,
          itemBuilder: (c, i) => ListTile(
            dense: true,
            title: Text(widget.outline[i].$1),
            trailing: Text('${widget.outline[i].$2}'),
            onTap: () {
              Navigator.pop(c);
              _goTo(widget.outline[i].$2);
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.book;
    return Scaffold(
      appBar: AppBar(
        title: Text(b.title, overflow: TextOverflow.ellipsis),
        actions: [
          if (widget.outline.isNotEmpty) IconButton(icon: const Icon(Icons.list), tooltip: 'Contents', onPressed: _showContents),
          IconButton(icon: const Icon(Icons.pin_outlined), tooltip: 'Go to page', onPressed: _askPage),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'About this book',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (c) => AlertDialog(
                title: Text(b.title),
                content: Text('${b.subtitle}\n\n${b.credit}'),
                actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
              ),
            ),
          ),
        ],
      ),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Could not open the book: $_error')))
          : _path == null
              ? const Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Getting the book ready (first time only)…'),
                  ]),
                )
              : Stack(children: [
                  PdfViewer.file(
                    _path!,
                    controller: _controller,
                    initialPageNumber: _start,
                    params: PdfViewerParams(
                      backgroundColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF222222) : const Color(0xFFE8E8E8),
                      onViewerReady: (doc, controller) {
                        if (mounted) setState(() => _count = doc.pages.length);
                      },
                      onPageChanged: (n) {
                        if (n == null) return;
                        _current = n;
                        _remember(n);
                        if (mounted) setState(() {});
                      },
                    ),
                  ),
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: Material(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: _askPage,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          child: Text(_count > 0 ? '$_current / $_count' : '$_current'),
                        ),
                      ),
                    ),
                  ),
                ]),
    );
  }
}

/// A card list of the bundled old books (shown on the Read tab).
class OldBooksSection extends StatelessWidget {
  const OldBooksSection({super.key, required this.db});
  final BibleDb db;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text('Old books (PDF)', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
      ),
      for (final b in allScans)
        ListTile(
          leading: const Icon(Icons.picture_as_pdf_outlined),
          title: Text(b.title),
          subtitle: Text(b.subtitle),
          onTap: () => openScan(context, b, outline: b.id == kjv1611.id ? db.outline1611() : const []),
        ),
    ]);
  }
}
