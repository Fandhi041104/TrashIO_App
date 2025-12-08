import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import 'firebase_options.dart';
import 'log_history.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const SmartTrashApp());
}

class SmartTrashApp extends StatelessWidget {
  const SmartTrashApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Trash Monitor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D0D0D),
        fontFamily: 'Inter',
        primaryColor: const Color(0xFF16A34A),
      ),
      home: const TrashMonitorScreen(),
    );
  }
}

class TrashMonitorScreen extends StatefulWidget {
  const TrashMonitorScreen({super.key});

  @override
  State<TrashMonitorScreen> createState() => _TrashMonitorScreenState();
}

class _TrashMonitorScreenState extends State<TrashMonitorScreen> {
  final DatabaseReference _trashRef = FirebaseDatabase.instance.ref('trashbin');
  final DatabaseReference _logsRef = FirebaseDatabase.instance.ref('trashbin_logs');
  final DatabaseReference _openCountRef = FirebaseDatabase.instance.ref('trashbin/open_count');

  double fillLevel = 0;
  double gasLevel = 0;
  bool servoOpen = false;
  bool prevServoOpen = false;
  int openCount = 0;
  String status = 'Waiting for data...';
  bool isConnected = false;
  String lastUpdate = '--:--:--';

  StreamSubscription<DatabaseEvent>? _trashSub;
  StreamSubscription<DatabaseEvent>? _connSub;

  @override
  void initState() {
    super.initState();
    _startListeners();
  }

  @override
  void dispose() {
    _trashSub?.cancel();
    _connSub?.cancel();
    super.dispose();
  }

  void _startListeners() {
    _trashSub = _trashRef.onValue.listen((event) {
      final snap = event.snapshot;
      if (snap.value == null) return;
      final Map data = Map<String, dynamic>.from(snap.value as Map);

      final gas = double.tryParse(data['gas_level']?.toString() ?? '') ?? gasLevel;
      final percent = double.tryParse(data['trash_percentage']?.toString() ?? '') ?? fillLevel;
      final servo = (data['servo_open'] == true);
      final st = data['status']?.toString() ?? status;
      final last = data['last_update']?.toString() ?? _now();

      setState(() {
        gasLevel = gas;
        fillLevel = percent;
        status = st;
        lastUpdate = _formatLastUpdate(last);
        servoOpen = servo;
      });

      if (!prevServoOpen && servoOpen) {
        _incrementOpenCountAndLog();
      }
      prevServoOpen = servoOpen;
    });

    _connSub = FirebaseDatabase.instance.ref('.info/connected').onValue.listen((event) {
      final val = event.snapshot.value;
      setState(() {
        isConnected = val == true;
        if (!isConnected) status = 'Not Connected';
      });
    });

    _openCountRef.get().then((snap) {
      if (snap.exists && snap.value != null) {
        final v = int.tryParse(snap.value.toString()) ?? 0;
        setState(() => openCount = v);
      }
    });
  }

  String _now() => DateTime.now().toIso8601String();

  String _formatLastUpdate(String raw) {
    try {
      if (raw.contains(RegExp(r'^\d+$'))) {
        final ms = int.parse(raw);
        final dt = DateTime.fromMillisecondsSinceEpoch(ms);
        return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } else {
        final dt = DateTime.parse(raw);
        return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
    } catch (_) {
      return raw;
    }
  }

  Future<void> _incrementOpenCountAndLog() async {
    try {
      await _openCountRef.runTransaction((currentData) {
        final current = (currentData == null)
            ? 0
            : int.tryParse(currentData.toString()) ?? 0;

        return Transaction.success(current + 1);
      });

      final snap = await _openCountRef.get();
      final newVal = snap.exists
          ? int.tryParse(snap.value.toString()) ?? openCount
          : openCount;

      setState(() => openCount = newVal);

      await _logsRef.push().set({
        'timestamp': DateTime.now().toIso8601String(),
        'event': 'Lid opened (servo)',
        'open_count': newVal,
      });
    } catch (e) {
      debugPrint('increment/open_count error: $e');
    }
  }

  Future<void> _onRefresh() async {
    final snap = await _trashRef.get();
    if (snap.exists && snap.value != null) {
      final map = Map<String, dynamic>.from(snap.value as Map);
      setState(() {
        gasLevel = double.tryParse(map['gas_level']?.toString() ?? '') ?? gasLevel;
        fillLevel = double.tryParse(map['trash_percentage']?.toString() ?? '') ?? fillLevel;
        status = map['status']?.toString() ?? status;
        lastUpdate = _formatLastUpdate(map['last_update']?.toString() ?? _now());
      });
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Realtime data refreshed')),
    );
  }

  Color _fillColor() {
    if (fillLevel >= 60) return const Color(0xFFDC2626);
    return const Color(0xFF16A34A);
  }

  Color _gasColor() {
    if (gasLevel >= 250) return const Color(0xFFDC2626);
    return const Color(0xFF16A34A);
  }

  String _fillStatusText() {
    if (fillLevel >= 80) return 'CRITICAL';
    if (fillLevel >= 60) return 'WARNING';
    return 'NORMAL';
  }

  String _gasStatusText() {
    if (gasLevel >= 350) return 'DANGER';
    if (gasLevel >= 250) return 'WARNING';
    return 'SAFE';
  }

  // ---------------- UI -----------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: _buildSidebar(),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _onRefresh,
          color: const Color(0xFFDC2626),
          child: LayoutBuilder(builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 900;

            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                children: [
                  _buildHeader(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: Column(
                      children: [
                        // Grid 2x2 untuk mobile, Row untuk desktop
                        isWide 
                          ? _buildStatusCardsRow() 
                          : _buildStatusCardsGrid(),
                        const SizedBox(height: 16),
                        _buildTrashCapacityCard(),
                        const SizedBox(height: 16),
                        _buildGasCard(),
                        const SizedBox(height: 16),
                        _buildDeviceInfoCard(),
                        const SizedBox(height: 30),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }

  // Header
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: const BoxDecoration(
        color: Color(0xFF0F0F0F),
        border: Border(bottom: BorderSide(color: Color(0xFF1A1A1A))),
      ),
      child: Row(
        children: [
          Builder(builder: (context) {
            return IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              onPressed: () => Scaffold.of(context).openDrawer(),
            );
          }),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('SMART TRASH', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Row(children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isConnected ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(isConnected ? status : 'Waiting for data...',
                    style: const TextStyle(color: Colors.white70)),
              ]),
            ],
          ),
          const Spacer(),
          Container(
            decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(8)),
            child: IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: _onRefresh,
            ),
          ),
        ],
      ),
    );
  }

  // Drawer
  Widget _buildSidebar() {
    return Drawer(
      backgroundColor: const Color(0xFF111111),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: Color(0xFF121212)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('SMART TRASH', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                SizedBox(height: 4),
                Text('Monitoring System', style: TextStyle(color: Colors.white70)),
              ],
            ),
          ),
          ListTile(
              leading: const Icon(Icons.dashboard),
              title: const Text('Dashboard'),
              onTap: () => Navigator.pop(context)),
          ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Log Riwayat'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const LogHistoryScreen()));
              }),
          const Divider(color: Colors.white10),
          ListTile(
            leading: const Icon(Icons.info),
            title: const Text('Tentang Device'),
            onTap: () {
              Navigator.pop(context);
              showAboutDialog(
                context: context,
                applicationName: 'Smart Trash Monitor',
                applicationVersion: '1.0',
                children: const [
                  Text('Monitoring tempat sampah cerdas'),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // ---------- STATUS CARDS - GRID 2x2 untuk Mobile ----------
  Widget _buildStatusCardsGrid() {
    return Column(
      children: [
        // Baris pertama: FILL LEVEL dan GAS LEVEL
        Row(
          children: [
            Expanded(
              child: _miniCard(
                'FILL LEVEL', 
                '${fillLevel.toStringAsFixed(0)}%', 
                _fillStatusText(), 
                _fillColor()
              )
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _miniCard(
                'GAS LEVEL', 
                '${gasLevel.toStringAsFixed(0)}', 
                _gasStatusText(), 
                _gasColor()
              )
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Baris kedua: OPEN COUNT dan CONNECTION
        Row(
          children: [
            Expanded(
              child: _miniCard(
                'OPEN COUNT', 
                '$openCount x', 
                'ACTIVITY', 
                const Color(0xFF3B82F6)
              )
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _miniCard(
                'CONNECTION',
                isConnected ? 'ONLINE' : 'OFFLINE',
                isConnected ? 'ACTIVE' : 'NO CONNECTION',
                isConnected ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
              )
            ),
          ],
        ),
      ],
    );
  }

  // ---------- STATUS CARDS - ROW untuk Desktop ----------
  Widget _buildStatusCardsRow() {
    return Row(
      children: [
        Expanded(child: _miniCard('FILL LEVEL', '${fillLevel.toStringAsFixed(0)}%', _fillStatusText(), _fillColor())),
        const SizedBox(width: 12),
        Expanded(child: _miniCard('GAS LEVEL', '${gasLevel.toStringAsFixed(0)}', _gasStatusText(), _gasColor())),
        const SizedBox(width: 12),
        Expanded(child: _miniCard('OPEN COUNT', '$openCount x', 'ACTIVITY', const Color(0xFF3B82F6))),
        const SizedBox(width: 12),
        Expanded(
          child: _miniCard(
            'CONNECTION',
            isConnected ? 'ONLINE' : 'OFFLINE',
            isConnected ? 'ACTIVE' : 'NO CONNECTION',
            isConnected ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
          ),
        ),
      ],
    );
  }

  Widget _miniCard(String label, String value, String statusText, Color accent) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: const Color(0xFF121212),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.withOpacity(0.3), width: 1)),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.6))),
            const SizedBox(height: 8),
            Text(value,
                style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: accent)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(statusText,
                  style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 11)),
            ),
          ]
      ),
    );
  }

  // -------------------- BIG CARDS ----------------------
  Widget _buildTrashCapacityCard() {
    final fillColor = _fillColor();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: const Color(0xFF121212),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('TRASH CAPACITY',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 18),
          Center(
            child: Container(
              width: 220,
              height: 340,
              decoration: BoxDecoration(
                  color: const Color(0xFF0A0A0A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10, width: 2)),
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      width: double.infinity,
                      height: (fillLevel / 100) * 340,
                      decoration: BoxDecoration(
                        color: fillColor,
                        borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(10),
                            bottomRight: Radius.circular(10)),
                      ),
                    ),
                  ),
                  Center(
                      child: Text('${fillLevel.toStringAsFixed(0)}%',
                          style: const TextStyle(
                              fontSize: 44,
                              fontWeight: FontWeight.w900,
                              color: Colors.white54))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: fillLevel / 100,
              minHeight: 8,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation(fillColor),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Current Level',
                  style: TextStyle(color: Colors.white.withOpacity(0.5))),
              Text('${fillLevel.toStringAsFixed(1)}%',
                  style: TextStyle(
                      color: fillColor, fontWeight: FontWeight.w700)),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildGasCard() {
    final gasColor = _gasColor();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: const Color(0xFF121212),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('GAS MONITOR',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontWeight: FontWeight.w700)),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                      color: gasColor.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(_gasStatusText(),
                      style: TextStyle(
                          color: gasColor, fontWeight: FontWeight.w800)),
                ),
              ]),
          const SizedBox(height: 16),
          Row(children: [
            Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: gasColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.air, color: gasColor)),
            const SizedBox(width: 16),
            Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Current Reading',
                      style: TextStyle(color: Colors.white.withOpacity(0.6))),
                  const SizedBox(height: 6),
                  Text('${gasLevel.toStringAsFixed(0)} ppm',
                      style: TextStyle(
                          color: gasColor,
                          fontWeight: FontWeight.w900,
                          fontSize: 28)),
                ]),
          ]),
          const SizedBox(height: 16),
          ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                  value: gasLevel / 500,
                  minHeight: 8,
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation(gasColor))),
          const SizedBox(height: 8),
          Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('0 ppm',
                    style: TextStyle(color: Colors.white.withOpacity(0.4))),
                Text('500 ppm',
                    style: TextStyle(color: Colors.white.withOpacity(0.4))),
              ]),
        ],
      ),
    );
  }

  Widget _buildDeviceInfoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: const Color(0xFF121212),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('DEVICE INFO',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          _infoRow(Icons.schedule, 'Last Update', lastUpdate),
          const SizedBox(height: 12),
          _infoRow(Icons.location_on_outlined, 'Location', 'Main Building'),
          const SizedBox(height: 12),
          _infoRow(Icons.sensors, 'Device ID', 'TRASH-001'),
          const SizedBox(height: 12),
          _infoRow(Icons.cloud_outlined, 'Status',
              isConnected ? status : 'Not Connected'),
          const SizedBox(height: 12),
          _infoRow(Icons.open_in_new, 'Lid Open Count', '$openCount x'),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(children: [
      Icon(icon, color: Colors.white38, size: 16),
      const SizedBox(width: 12),
      Text(label, style: TextStyle(color: Colors.white.withOpacity(0.6))),
      const Spacer(),
      Text(value,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
    ]);
  }
}