import 'package:flutter/material.dart';
import 'package:omni_core_ui/omni_core_ui.dart' show HubConnectionState, OmniOta;
import '../net/omni_node.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _tokenController = TextEditingController(text: omniNode.token);
  bool _saved = false;
  bool _checking = false;
  int _localEvents = 0;

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
    final n = await omniNode.localEventCount();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _localEvents = n;
    });
  }

  Color get _dotColor {
    final c = omniNode.lastConnection;
    if (_checking || c == null) return Colors.grey;
    if (c.connected) return Colors.greenAccent;
    if (c.state == HubConnectionState.unreachable) return Colors.redAccent;
    return Colors.orangeAccent;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F18),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('SETTINGS • OMNI NODE', style: TextStyle(color: Color(0xFF00E5FF))),
        iconTheme: const IconThemeData(color: Color(0xFF00E5FF)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Connection status: dot + words.
                Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(color: _dotColor, shape: BoxShape.circle),
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
                      icon: const Icon(Icons.refresh, color: Color(0xFF00E5FF)),
                      onPressed: _checking ? null : _refresh,
                    ),
                  ],
                ),
                const Text(
                  'Omni Node on this phone (127.0.0.1)',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 24),
                const Text('Omni Node token', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 6),
                TextField(
                  controller: _tokenController,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFF1E293B),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    hintText: 'Paste the token here',
                    hintStyle: const TextStyle(color: Colors.white38),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Open Omni Node > Connect apps (unlock your screen when asked), tap Copy token, '
                  'then paste it here.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E5FF),
                      foregroundColor: Colors.black,
                    ),
                    onPressed: () async {
                      await omniNode.saveToken(_tokenController.text);
                      if (!mounted) return;
                      setState(() => _saved = true);
                      await _refresh();
                      Future.delayed(const Duration(seconds: 1), () {
                        if (mounted) setState(() => _saved = false);
                      });
                    },
                    child: const Text('SAVE SETTINGS', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                if (_saved) ...[
                  const SizedBox(height: 16),
                  const Center(
                    child: Text('Settings saved successfully!', style: TextStyle(color: Colors.greenAccent)),
                  ),
                ],
                const SizedBox(height: 28),
                const Text('What is connected', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 8),
                _line('Your player key',
                    omniNode.shortId.isEmpty ? 'Not created yet' : 'Ed25519 ${omniNode.shortId}'),
                _line('Fight events', 'Signed and saved on this phone ($_localEvents)'),
                _line('Sharing fights with Omni Node', notWiredYet),
                _line('Your fighter (Live Persona Engine)', '$notWiredYet: offline persona'),
                _line('Opponent (OmniMind)', '$notWiredYet: offline persona'),
                const SizedBox(height: 24),
                TextButton.icon(
                  icon: const Icon(Icons.system_update, color: Color(0xFF00E5FF)),
                  label: const Text('Check for updates', style: TextStyle(color: Color(0xFF00E5FF))),
                  onPressed: () => OmniOta.checkAndPrompt(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _line(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13))),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: value.startsWith(notWiredYet) ? Colors.orangeAccent : Colors.white,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
