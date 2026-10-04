import 'package:flutter/material.dart';

import 'prefs.dart';

/// Highlight colors (light and dark variants).
const highlightColorsLight = [Color(0xFFFFF1A8), Color(0xFFCDEFC4), Color(0xFFBFE0FA), Color(0xFFF8CFE0)];
const highlightColorsDark = [Color(0x66E5C300), Color(0x6648A63A), Color(0x663D8FD8), Color(0x66D8508C)];

Color highlightColor(BuildContext context, int i) =>
    (Theme.of(context).brightness == Brightness.dark ? highlightColorsDark : highlightColorsLight)[i % 4];

/// Turns a verse's markup (<i> added words, <j> words of Jesus) into styled spans.
List<InlineSpan> markupSpans(
  String markup, {
  required TextStyle base,
  required bool italics,
  required bool red,
  required Color redColor,
}) {
  final spans = <InlineSpan>[];
  var ital = false;
  var jesus = false;
  for (final m in RegExp(r'<(/?)([ij])>|([^<]+)').allMatches(markup)) {
    if (m.group(3) != null) {
      spans.add(TextSpan(
        text: m.group(3),
        style: base.copyWith(
          fontStyle: ital && italics ? FontStyle.italic : null,
          color: jesus && red ? redColor : null,
        ),
      ));
    } else {
      final close = m.group(1) == '/';
      if (m.group(2) == 'i') ital = !close;
      if (m.group(2) == 'j') jesus = !close;
    }
  }
  return spans;
}

/// "John 3:16-17" style label for a sorted list of verse numbers in one chapter.
String verseRange(List<int> verses) {
  if (verses.isEmpty) return '';
  final out = <String>[];
  var start = verses.first, prev = verses.first;
  for (final v in verses.skip(1)) {
    if (v == prev + 1) {
      prev = v;
      continue;
    }
    out.add(start == prev ? '$start' : '$start-$prev');
    start = prev = v;
  }
  out.add(start == prev ? '$start' : '$start-$prev');
  return out.join(', ');
}

Color redLetterColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark ? const Color(0xFFFF8A80) : const Color(0xFFB3261E);

TextStyle readingStyle(BuildContext context) {
  final base = Theme.of(context).textTheme.bodyLarge ?? const TextStyle();
  return base.copyWith(
    fontSize: 19 * Prefs.fontScale.value,
    height: Prefs.lineHeight.value,
    fontFamily: Prefs.serif.value ? 'serif' : null,
  );
}
