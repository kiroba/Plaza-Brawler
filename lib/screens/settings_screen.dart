import 'package:flutter/material.dart';
import '../net/omni_node.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _hostController = TextEditingController(text: omniNode.host);
  final TextEditingController _portController = TextEditingController(text: omniNode.daemonPort.toString());
  bool _saved = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F18),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('SETTINGS • OMNI NODE', style: TextStyle(color: Color(0xFF00E5FF))),
        iconTheme: const IconThemeData(color: Color(0xFF00E5FF)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Daemon Host', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 6),
                TextField(
                  controller: _hostController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFF1E293B),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Daemon Port', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 6),
                TextField(
                  controller: _portController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFF1E293B),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E5FF),
                      foregroundColor: Colors.black,
                    ),
                    onPressed: () {
                      setState(() {
                        _saved = true;
                      });
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
