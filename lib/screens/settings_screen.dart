// Settings (spec 4.7, 4.8, 5). Kept: Omni Node token entry, connection dot + words, "Check for updates"
// (OmniOta.checkAndPrompt). Added: real status lines for the LPE fighter, OmniMind opponents and match sharing,
// the "Share my match results" toggle (off for every install; shown disabled, "turns on when Omni Node
// supports it", until the node can receive match results), a "Sound effects" switch (mute),
// feedback summary + CSV export (share sheet), Reset demo data, and Demo-day mode (set a 4-digit PIN to turn
// it on; turning it off clears the PIN). The whole screen is hidden while Demo-day mode is on.
import 'package:flutter/material.dart';
import 'package:omni_core_ui/omni_core_ui.dart'
    show HubConnectionState, OmniOta;

import '../app_state.dart';
import '../game/kiosk.dart';
import '../net/match_share.dart';
import '../net/omni_node.dart';
import 'brawler_ui.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _tokenController = TextEditingController(
    text: omniNode.token,
  );
  bool _saved = false;
  bool _checking = false;
  int _localEvents = 0;
  String _feedbackSummary = '...';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _checking = true);
    await omniNode.checkConnection();
    await omniNode.refreshLpe();
    await omniNode.probeOmniMind();
    final n = await omniNode.localEventCount();
    final fb = await appState.feedback.summary();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _localEvents = n;
      _feedbackSummary = fb;
    });
    appState.refresh();
  }

  Color get _dotColor {
    final c = omniNode.lastConnection;
    if (_checking || c == null) return Colors.grey;
    if (c.connected) return Colors.greenAccent;
    if (c.state == HubConnectionState.unreachable) return Colors.redAccent;
    return Colors.orangeAccent;
  }

  Future<void> _turnOnKiosk() async {
    final pin = await showDialog<String>(
      context: context,
      builder: (_) => const _SetPinDialog(),
    );
    if (pin == null) return;
    final ok = await appState.enableKiosk(pin);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The PIN must be exactly 4 digits.')),
      );
      return;
    }
    // Settings is hidden in Demo-day mode: back to the title.
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _resetData() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Reset demo data?'),
        content: const Text(
          'This deletes every high score and feedback response on this phone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    await appState.resetDemoData();
    await _refresh();
  }

  Future<void> _exportFeedback() async {
    final ok = await appState.feedback.shareCsv();
    if (!mounted || ok) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('No feedback to share yet.')));
  }

  @override
  Widget build(BuildContext context) {
    return BrawlerPage(
      title: 'SETTINGS',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Connection status: dot + words.
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: _dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _checking ? 'Checking Omni Node...' : omniNode.statusWords,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              IconButton(
                tooltip: 'Check again',
                icon: const Icon(Icons.refresh, color: BrawlerColors.cyan),
                onPressed: _checking ? null : _refresh,
              ),
            ],
          ),
          const Text(
            'Omni Node on this phone (127.0.0.1)',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 20),
          const Text(
            'Omni Node token',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _tokenController,
            obscureText: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              filled: true,
              fillColor: BrawlerColors.panel,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              hintText: 'Paste the token here',
              hintStyle: const TextStyle(color: Colors.white38),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Open Omni Node > Connect apps (unlock your screen when asked), tap Copy token, then paste it here.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 12),
          BigButton(
            'SAVE SETTINGS',
            onPressed: () async {
              await omniNode.saveToken(_tokenController.text);
              if (!mounted) return;
              setState(() => _saved = true);
              await _refresh();
              Future.delayed(const Duration(seconds: 1), () {
                if (mounted) setState(() => _saved = false);
              });
            },
          ),
          if (_saved)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Center(
                child: Text(
                  'Settings saved.',
                  style: TextStyle(color: Colors.greenAccent),
                ),
              ),
            ),
          const SizedBox(height: 24),
          const Text(
            'What is connected',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 8),
          _line(
            'Your player key',
            omniNode.shortId.isEmpty
                ? 'Not created yet'
                : 'Ed25519 ${omniNode.shortId}',
          ),
          _line(
            'Fight events',
            'Signed and saved on this phone ($_localEvents)',
          ),
          _line(
            'Your fighter (Live Persona Engine)',
            omniNode.lpeStatus,
            ok: omniNode.lpeConnected,
          ),
          _line(
            'Opponent (OmniMind)',
            omniNode.omniMindStatus,
            ok: omniNode.omniMindConnected,
          ),
          _line('Sharing fights with Omni Node', matchShareStatus),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Share my match results',
              style: TextStyle(
                color: AppState.nodeAcceptsMatchShares
                    ? Colors.white
                    : Colors.white54,
              ),
            ),
            subtitle: Text(
              AppState.nodeAcceptsMatchShares
                  ? 'Off by default. Turn on to send your results to Omni Node.'
                  : 'Off. Turns on when Omni Node supports it; until then results stay on this phone.',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            // Waiting state: off and disabled until the node has a match endpoint.
            value: AppState.nodeAcceptsMatchShares && appState.shareEnabled,
            onChanged: AppState.nodeAcceptsMatchShares
                ? (v) async {
                    await appState.setShareEnabled(v);
                    if (mounted) setState(() {});
                  }
                : null,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Sound effects',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              'Hits, blocks, K.O. and menu clicks.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            value: appState.soundOn,
            onChanged: (v) async {
              await appState.setSoundOn(v);
              if (mounted) setState(() {});
            },
          ),
          const SizedBox(height: 16),
          const Text(
            'Playtest feedback',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 4),
          Text(
            _feedbackSummary,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          const SizedBox(height: 6),
          BigButton(
            'SHARE FEEDBACK AS CSV',
            icon: Icons.ios_share,
            color: BrawlerColors.panel,
            textColor: Colors.white,
            onPressed: _exportFeedback,
          ),
          BigButton(
            'RESET DEMO DATA',
            icon: Icons.delete_outline,
            color: BrawlerColors.panel,
            textColor: BrawlerColors.red,
            onPressed: _resetData,
          ),
          const SizedBox(height: 16),
          const Text('Demo-day mode', style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 4),
          const Text(
            'For a playtest table: attract loop after 20 s idle, auto-return to the title, screen stays on, '
            'fullscreen, Settings hidden. To leave it, hold the title logo for 3 s and enter the PIN.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Demo-day mode',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              appState.kioskOn ? 'On (PIN set)' : 'Off (no PIN set)',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            value: appState.kioskOn,
            onChanged: (v) async {
              if (v) {
                await _turnOnKiosk();
              } else {
                await appState.disableKiosk();
                if (mounted) setState(() {});
              }
            },
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            icon: const Icon(Icons.system_update, color: BrawlerColors.cyan),
            label: const Text(
              'Check for updates',
              style: TextStyle(color: BrawlerColors.cyan),
            ),
            onPressed: () => OmniOta.checkAndPrompt(context),
          ),
          Text(
            'Plaza Brawler ${AppState.appVersion}',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _line(String label, String value, {bool ok = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: ok
                    ? Colors.greenAccent
                    : (value.startsWith(notWiredYet)
                          ? Colors.orangeAccent
                          : Colors.white),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Asks for a new 4-digit PIN twice. Pops the PIN, or null on cancel.
class _SetPinDialog extends StatefulWidget {
  const _SetPinDialog();

  @override
  State<_SetPinDialog> createState() => _SetPinDialogState();
}

class _SetPinDialogState extends State<_SetPinDialog> {
  final TextEditingController _a = TextEditingController();
  final TextEditingController _b = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  void _ok() {
    final a = _a.text.trim(), b = _b.text.trim();
    if (!KioskPin.isValid(a)) {
      setState(() => _error = 'Use exactly 4 digits');
    } else if (a != b) {
      setState(() => _error = "The PINs don't match");
    } else {
      Navigator.of(context).pop(a);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Set a demo-day PIN'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _a,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              decoration: const InputDecoration(labelText: 'New PIN'),
            ),
            TextField(
              controller: _b,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              decoration: InputDecoration(
                labelText: 'Repeat PIN',
                errorText: _error,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _ok, child: const Text('Turn on')),
      ],
    );
  }
}
