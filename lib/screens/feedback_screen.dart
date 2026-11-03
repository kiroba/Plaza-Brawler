// Post-match feedback (spec 4.8). Real: 1-5 stars, up to 3 tap-tags, an optional one-line comment, saved in
// sqflite on this phone via FeedbackRepo (no names, no device ids). SKIP is always visible. Pops true when
// saved, false when skipped.
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../game/records.dart';
import 'brawler_ui.dart';

class FeedbackScreen extends StatefulWidget {
  final String mode;
  final String sign;
  final int reached;
  final int score;

  const FeedbackScreen({
    super.key,
    required this.mode,
    required this.sign,
    required this.reached,
    required this.score,
  });

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  int _stars = 0;
  final List<String> _tags = [];
  final TextEditingController _comment = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_stars == 0 || _saving) return;
    setState(() => _saving = true);
    await appState.feedback.add(
      FeedbackEntry(
        stars: _stars,
        tags: List.of(_tags),
        comment: _comment.text,
        mode: widget.mode,
        sign: widget.sign,
        reached: widget.reached,
        score: widget.score,
        appVersion: AppState.appVersion,
        ts: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return BrawlerPage(
      title: 'HOW WAS THAT?',
      showBack: false,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(
            'SKIP',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 1; i <= 5; i++)
                  IconButton(
                    iconSize: 44,
                    icon: Icon(
                      i <= _stars ? Icons.star : Icons.star_border,
                      color: BrawlerColors.gold,
                    ),
                    onPressed: () => setState(() => _stars = i),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              for (final t in FeedbackRules.tags)
                FilterChip(
                  label: Text(t),
                  selected: _tags.contains(t),
                  onSelected: (on) => setState(() {
                    if (on &&
                        !_tags.contains(t) &&
                        _tags.length < FeedbackRules.maxTags) {
                      _tags.add(t);
                    } else if (!on) {
                      _tags.remove(t);
                    }
                  }),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _comment,
            maxLength: FeedbackRules.maxComment,
            maxLines: 1,
            onChanged: (_) => appState.kiosk.noteActivity(),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              filled: true,
              fillColor: BrawlerColors.panel,
              hintText: 'Anything else? (optional)',
              hintStyle: const TextStyle(color: Colors.white38),
              counterStyle: const TextStyle(color: Colors.white38),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 8),
          BigButton('SEND', onPressed: _stars == 0 || _saving ? null : _save),
          BigButton(
            'SKIP',
            color: BrawlerColors.panel,
            textColor: Colors.white,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          const Text(
            'Saved on this phone only. No names, no device IDs.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
