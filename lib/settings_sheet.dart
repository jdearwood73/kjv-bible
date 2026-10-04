import 'package:flutter/material.dart';

import 'prefs.dart';

/// Bottom sheet with reading settings. Changes apply immediately.
Future<void> showSettingsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _SettingsSheet(),
  );
}

class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: AnimatedBuilder(
          animation: Listenable.merge([
            Prefs.fontScale,
            Prefs.lineHeight,
            Prefs.serif,
            Prefs.theme,
            Prefs.redLetters,
            Prefs.showItalics,
          ]),
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Reading settings', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Row(children: [
                const Text('A', style: TextStyle(fontSize: 14)),
                Expanded(
                  child: Slider(
                    value: Prefs.fontScale.value,
                    min: 0.7,
                    max: 2.2,
                    divisions: 15,
                    label: '${(Prefs.fontScale.value * 100).round()}%',
                    onChanged: Prefs.setFontScale,
                  ),
                ),
                const Text('A', style: TextStyle(fontSize: 28)),
              ]),
              Row(children: [
                const Icon(Icons.format_line_spacing, size: 20),
                Expanded(
                  child: Slider(
                    value: Prefs.lineHeight.value,
                    min: 1.2,
                    max: 2.2,
                    divisions: 10,
                    label: Prefs.lineHeight.value.toStringAsFixed(1),
                    onChanged: Prefs.setLineHeight,
                  ),
                ),
                const Text('Spacing'),
              ]),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Serif')),
                  ButtonSegment(value: false, label: Text('Sans')),
                ],
                selected: {Prefs.serif.value},
                onSelectionChanged: (s) => Prefs.setSerif(s.first),
              ),
              const SizedBox(height: 12),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('Auto')),
                  ButtonSegment(value: 1, label: Text('Light')),
                  ButtonSegment(value: 2, label: Text('Sepia')),
                  ButtonSegment(value: 3, label: Text('Dark')),
                ],
                selected: {Prefs.theme.value},
                onSelectionChanged: (s) => Prefs.setTheme(s.first),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Words of Jesus in red'),
                value: Prefs.redLetters.value,
                onChanged: Prefs.setRedLetters,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Italics for supplied words'),
                subtitle: const Text('The KJV prints added words in italics'),
                value: Prefs.showItalics.value,
                onChanged: Prefs.setShowItalics,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
