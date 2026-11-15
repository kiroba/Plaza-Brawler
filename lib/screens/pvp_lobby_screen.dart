// PvP lobby (slices S1 + S2): host a session or join one, on the same
// LAN. Host shows a QR code with the pairing payload plus a 6-digit
// session code; the guest joins with the code + host IP (in-app QR
// scanning lands in a later slice). Once the S1 handshake completes, the
// S2 start exchange swaps each side's picked fighter sign and the fight
// runs in lockstep (lib/net/pvp_lockstep.dart). Either side leaving (or
// the peer dropping) returns both phones here; single-player is
// untouched.
import 'package:flutter/material.dart';
import 'package:omni_core_ui/omni_core_ui.dart' show StargateIdentity;
import 'package:qr_flutter/qr_flutter.dart';

import '../app_state.dart';
import '../net/omni_node.dart';
import '../net/pvp_lockstep.dart';
import '../net/pvp_session.dart';
import '../npc/zodiac_offline.dart';
import 'brawler_ui.dart';
import 'fighter_screen.dart';
import 'game_over_screen.dart';

class PvpLobbyScreen extends StatefulWidget {
  const PvpLobbyScreen({super.key});

  @override
  State<PvpLobbyScreen> createState() => _PvpLobbyScreenState();
}

enum _Mode { host, join }

class _PvpLobbyScreenState extends State<PvpLobbyScreen> {
  _Mode _mode = _Mode.host;
  StargateIdentity? _identity;
  PvpHost? _host;
  PvpSession? _session;
  bool _busy = false;
  bool _ended = false;

  /// True while a lockstep match is on screen: the session's done
  /// listener stays quiet and the match flow owns the end state.
  bool _inMatch = false;
  String _status = '';
  String? _error;
  final _codeController = TextEditingController();
  final _ipController = TextEditingController();
  final _portController = TextEditingController(
    text: pvpDefaultPort.toString(),
  );

  @override
  void initState() {
    super.initState();
    _loadIdentity();
  }

  Future<void> _loadIdentity() async {
    final identity = await omniNode.loadIdentity();
    if (!mounted) return;
    setState(() {
      _identity = identity;
      if (identity == null || identity.pubkeyHex.isEmpty) {
        _error = 'Identity not ready — close and reopen the app, then try again.';
      }
    });
    if (identity != null && identity.pubkeyHex.isNotEmpty) {
      _startHosting();
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _ipController.dispose();
    _portController.dispose();
    _disposeHost();
    _session?.close();
    super.dispose();
  }

  void _disposeHost() {
    final host = _host;
    _host = null;
    host?.close();
  }

  Future<void> _startHosting() async {
    final identity = _identity;
    if (identity == null || _busy || _host != null) return;
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Starting the session…';
    });
    try {
      final host = await PvpHost.create(
        pubkeyHex: identity.pubkeyHex,
        sign: identity.signBytes,
      );
      if (!mounted) {
        await host.close();
        return;
      }
      setState(() {
        _host = host;
        _busy = false;
        _status = 'Waiting for the other phone…';
      });
      _waitForGuest(host);
    } on PvpError catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
        _status = '';
      });
    }
  }

  void _waitForGuest(PvpHost host) {
    host.waitForGuest().then((session) {
      if (!mounted || _host != host) {
        session.close();
        return;
      }
      _onConnected(session);
    }).catchError((Object e) {
      if (!mounted || _host != host) return;
      setState(() {
        _error = e is PvpError ? e.message : 'Waiting stopped.';
        _status = '';
      });
      _disposeHost();
    });
  }

  void _onConnected(PvpSession session) {
    setState(() {
      _session = session;
      _status = 'Connected — picking fighters…';
      _error = null;
      _ended = false;
    });
    session.done.then((_) {
      if (!mounted || _session != session || _inMatch) return;
      setState(() {
        _session = null;
        _ended = true;
        _error = 'The other phone left the session.';
        _status = '';
      });
    });
    _startMatch(session);
  }

  /// The sign this phone fights as: the player's saved pick, else their
  /// LPE profile's sign, else Aries. PvP builds both fighters from the
  /// sign alone (offlineFighter), so both phones construct identical
  /// fighters from the two signs and nothing else.
  String _mySign() {
    final picked = appState.chosenSign ?? omniNode.lpeSign;
    if (picked != null && offlineFighter(picked) != null) return picked;
    return 'aries';
  }

  /// S2: swap signed start messages, build the two fighters (host is
  /// always P1, guest always P2), run the lockstep fight, then show the
  /// normal game-over screen. The session closes when the match does —
  /// one match per session, as in S1.
  Future<void> _startMatch(PvpSession session) async {
    final identity = _identity;
    if (identity == null) return;
    final mySign = _mySign();
    try {
      final start = await pvpExchangeStart(
        session: session,
        myPubkey: identity.pubkeyHex,
        mySign: mySign,
        sign: identity.signBytes,
      );
      if (!mounted || _session != session) return;
      final hostDef = offlineFighter(session.isHost ? mySign : start.peerSign);
      final guestDef =
          offlineFighter(session.isHost ? start.peerSign : mySign);
      if (hostDef == null || guestDef == null) {
        throw const PvpError('A fighter pick did not check out.');
      }
      final driver = PvpLockstep.over(session);
      setState(() {
        _inMatch = true;
        _status = 'Match starting…';
      });
      final outcome = await Navigator.of(context).push<FightOutcome>(
        MaterialPageRoute(
          builder: (_) => FighterScreen(
            config: FightConfig(
              p1: hostDef,
              p2: guestDef,
              seed: start.seed,
              mode: 'pvp',
              lockstep: driver,
            ),
          ),
        ),
      );
      _inMatch = false;
      await driver.dispose();
      if (!mounted || _session != session) return;
      if (driver.aborted) {
        _disposeHost();
        await session.close();
        if (!mounted) return;
        setState(() {
          _session = null;
          _ended = true;
          _error = driver.abortReason ?? 'The match ended early.';
          _status = '';
        });
        return;
      }
      if (outcome == null) {
        // Backed out of the fight screen: end the session politely.
        await session.sendAbort('left');
        _disposeHost();
        await session.close();
        if (!mounted) return;
        setState(() {
          _session = null;
          _ended = true;
          _status = '';
        });
        return;
      }
      // Clean finish: the normal game-over screen, from my side's view.
      // Its RETRY button also lands back here — a rematch is a fresh
      // host/join in S2 (one match per session).
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => GameOverScreen(
            won: outcome.playerWon,
            player: session.isHost ? hostDef : guestDef,
            opponent: session.isHost ? guestDef : hostDef,
          ),
        ),
      );
      if (!mounted || _session != session) return;
      _disposeHost();
      await session.close();
      if (!mounted) return;
      final winner = outcome.summary['winner'];
      final mySide = session.isHost ? 'p1' : 'p2';
      setState(() {
        _session = null;
        _ended = true;
        _error = null;
        _status = winner == 'draw'
            ? 'The match was a draw.'
            : winner == mySide
                ? 'You won the match!'
                : 'You lost the match.';
      });
    } on PvpError catch (e) {
      if (!mounted || _session != session) return;
      await session.sendAbort('start failed');
      _disposeHost();
      await session.close();
      if (!mounted) return;
      setState(() {
        _session = null;
        _ended = true;
        _error = e.message;
        _status = '';
      });
    }
  }

  Future<void> _join() async {
    final identity = _identity;
    if (identity == null || _busy) return;
    final code = _codeController.text.trim();
    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim());
    if (code.length != 6 || int.tryParse(code) == null) {
      setState(() => _error = 'Enter the 6-digit code from the host phone.');
      return;
    }
    if (!_looksLikeIp(ip)) {
      setState(() => _error = 'Enter the host IP as shown on the host phone.');
      return;
    }
    if (port == null || port < 1 || port > 65535) {
      setState(() => _error = 'Enter the port as shown on the host phone.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Connecting to $ip:$port…';
    });
    try {
      final session = await PvpGuest.connectManual(
        hostIp: ip,
        port: port,
        code: code,
        pubkeyHex: identity.pubkeyHex,
        sign: identity.signBytes,
      );
      if (!mounted) {
        await session.close();
        return;
      }
      setState(() => _busy = false);
      _onConnected(session);
    } on PvpError catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
        _status = '';
      });
    }
  }

  bool _looksLikeIp(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null || n < 0 || n > 255) return false;
    }
    return true;
  }

  Future<void> _leave() async {
    final session = _session;
    _session = null;
    if (session != null) {
      await session.sendAbort('left');
      await session.close();
    }
    _disposeHost();
    if (mounted) Navigator.of(context).pop();
  }

  void _cancel() {
    _disposeHost();
    _session?.close();
    if (mounted) Navigator.of(context).pop();
  }

  void _switchMode(_Mode mode) {
    if (mode == _mode) return;
    _disposeHost();
    _session?.close();
    setState(() {
      _mode = mode;
      _session = null;
      _ended = false;
      _busy = false;
      _error = null;
      _status = '';
    });
    if (mode == _Mode.host) _startHosting();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return BrawlerPage(
      title: 'PLAY TOGETHER',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Two phones, one Wi-Fi, no server. One phone hosts, the other joins.',
            style: TextStyle(color: Colors.white70, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _ModeButton(
                  label: 'HOST',
                  selected: _mode == _Mode.host,
                  onPressed: () => _switchMode(_Mode.host),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ModeButton(
                  label: 'JOIN',
                  selected: _mode == _Mode.join,
                  onPressed: () => _switchMode(_Mode.join),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (session != null) ...[
            _ConnectedCard(
              peerShortId:
                  '${session.peerPubkey.substring(0, 4)}…${session.peerPubkey.substring(session.peerPubkey.length - 4)}',
              status: _status,
            ),
            const SizedBox(height: 16),
            BigButton(
              'LEAVE MATCH',
              icon: Icons.close,
              color: BrawlerColors.red,
              textColor: Colors.white,
              onPressed: _leave,
            ),
          ] else if (_mode == _Mode.host) ...[
            _HostCard(
              host: _host,
              busy: _busy,
              status: _status,
            ),
            const SizedBox(height: 16),
            BigButton(
              'CANCEL',
              icon: Icons.close,
              color: BrawlerColors.panel,
              textColor: Colors.white,
              onPressed: _cancel,
            ),
          ] else ...[
            _JoinForm(
              codeController: _codeController,
              ipController: _ipController,
              portController: _portController,
              busy: _busy,
              status: _status,
              onJoin: _join,
            ),
            const SizedBox(height: 16),
            BigButton(
              'BACK',
              icon: Icons.arrow_back,
              color: BrawlerColors.panel,
              textColor: Colors.white,
              onPressed: _cancel,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(
              _error!,
              style: const TextStyle(color: BrawlerColors.red, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
          if (_ended) ...[
            const SizedBox(height: 14),
            const Text(
              'Session ended. You can host or join again.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onPressed;
  const _ModeButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor:
              selected ? BrawlerColors.cyan : BrawlerColors.panel,
          foregroundColor: selected ? Colors.black : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        onPressed: onPressed,
        child: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
      ),
    );
  }
}

class _HostCard extends StatelessWidget {
  final PvpHost? host;
  final bool busy;
  final String status;
  const _HostCard({this.host, required this.busy, required this.status});

  @override
  Widget build(BuildContext context) {
    final runningHost = host;
    final payload = runningHost?.payload;
    if (payload == null || runningHost == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: CircularProgressIndicator(color: BrawlerColors.cyan),
        ),
      );
    }
    // Short screens (landscape phones): a smaller QR + code so the host
    // card fits with no scrolling. 150 dp still scans fine at arm's length.
    final compact = MediaQuery.sizeOf(context).height < 520;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: QrImageView(
            data: payload.toQrString(),
            version: QrVersions.auto,
            size: compact ? 150 : 200,
            backgroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'The other phone scans this in a later slice — for now it types the code:',
          style: TextStyle(color: Colors.white70, fontSize: 12),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          runningHost.sessionCode,
          style: TextStyle(
            color: BrawlerColors.gold,
            fontSize: compact ? 32 : 40,
            fontWeight: FontWeight.w900,
            letterSpacing: 8,
          ),
        ),
        Text(
          '${payload.hostIp}:${payload.port}',
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        const SizedBox(height: 10),
        Text(
          status,
          style: const TextStyle(color: BrawlerColors.cyan, fontSize: 13),
          textAlign: TextAlign.center,
        ),
        if (busy)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: CircularProgressIndicator(color: BrawlerColors.cyan),
          ),
      ],
    );
  }
}

class _JoinForm extends StatelessWidget {
  final TextEditingController codeController;
  final TextEditingController ipController;
  final TextEditingController portController;
  final bool busy;
  final String status;
  final VoidCallback onJoin;
  const _JoinForm({
    required this.codeController,
    required this.ipController,
    required this.portController,
    required this.busy,
    required this.status,
    required this.onJoin,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: codeController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(
            labelText: 'Session code (6 digits)',
            counterText: '',
          ),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w900,
            letterSpacing: 6,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: ipController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Host IP (e.g. 192.168.1.5)',
          ),
          style: const TextStyle(color: Colors.white),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: portController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Port'),
          style: const TextStyle(color: Colors.white),
        ),
        const SizedBox(height: 14),
        BigButton(
          'CONNECT',
          icon: Icons.link,
          onPressed: busy ? null : onJoin,
        ),
        if (status.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            status,
            style: const TextStyle(color: BrawlerColors.cyan, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
        if (busy)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Center(
              child: CircularProgressIndicator(color: BrawlerColors.cyan),
            ),
          ),
      ],
    );
  }
}

class _ConnectedCard extends StatelessWidget {
  final String peerShortId;
  final String status;
  const _ConnectedCard({required this.peerShortId, required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BrawlerColors.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BrawlerColors.cyan, width: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, color: Colors.greenAccent, size: 40),
          const SizedBox(height: 8),
          Text(
            'Connected to $peerShortId',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            status,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
