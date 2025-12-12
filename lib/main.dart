import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:fl_chart/fl_chart.dart';

import 'firebase_options.dart';
import 'log_history.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
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

// Data class untuk chart
class ChartData {
  final DateTime time;
  final double value;
  ChartData(this.time, this.value);
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
  bool isDataReceived = false;
  String lastUpdate = '--:--:--';
  
  List<FlSpot> fillHistory = [];
  List<FlSpot> gasHistory = [];

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
      if (snap.value == null) {
        setState(() => isDataReceived = false);
        return;
      }
      
      setState(() => isDataReceived = true);
      
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
        _updateChartData();
      });

      if (!prevServoOpen && servoOpen) _incrementOpenCountAndLog();
      prevServoOpen = servoOpen;
    });

    _connSub = FirebaseDatabase.instance.ref('.info/connected').onValue.listen((event) {
      setState(() => isConnected = event.snapshot.value == true);
    });

    _openCountRef.get().then((snap) {
      if (snap.exists && snap.value != null) {
        setState(() => openCount = int.tryParse(snap.value.toString()) ?? 0);
      }
    });
  }

  void _updateChartData() {
    if (fillHistory.length >= 15) {
      fillHistory.removeAt(0);
      gasHistory.removeAt(0);
    }
    final x = fillHistory.length.toDouble();
    fillHistory.add(FlSpot(x, fillLevel));
    gasHistory.add(FlSpot(x, gasLevel));
  }

  String _now() => DateTime.now().toIso8601String();

  String _formatLastUpdate(String raw) {
    try {
      if (raw.contains(RegExp(r'^\d+$'))) {
        final dt = DateTime.fromMillisecondsSinceEpoch(int.parse(raw));
        return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
      final dt = DateTime.parse(raw);
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw;
    }
  }

  Future<void> _incrementOpenCountAndLog() async {
    try {
      await _openCountRef.runTransaction((currentData) {
        final current = (currentData == null) ? 0 : int.tryParse(currentData.toString()) ?? 0;
        return Transaction.success(current + 1);
      });

      final snap = await _openCountRef.get();
      final newVal = snap.exists ? int.tryParse(snap.value.toString()) ?? openCount : openCount;
      setState(() => openCount = newVal);

      await _logsRef.push().set({
        'timestamp': DateTime.now().toIso8601String(),
        'event': 'Lid opened (servo)',
        'open_count': newVal,
      });
    } catch (e) {
      debugPrint('Error: $e');
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
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Data refreshed')),
      );
    }
  }

  Color _fillColor() => fillLevel >= 60 ? const Color(0xFFDC2626) : const Color(0xFF16A34A);
  Color _gasColor() => gasLevel >= 250 ? const Color(0xFFDC2626) : const Color(0xFF16A34A);
  
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

  bool get _isReallyConnected => isConnected && isDataReceived;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: _buildModernSidebar(),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _onRefresh,
          color: const Color(0xFFDC2626),
          child: LayoutBuilder(builder: (ctx, constraints) {
            final isWide = constraints.maxWidth >= 900;
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                children: [
                  _buildHeader(),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        isWide ? _buildStatusCardsRow() : _buildStatusCardsGrid(),
                        const SizedBox(height: 16),
                        _buildTrashCapacityCard(),
                        const SizedBox(height: 16),
                        _buildGasCard(),
                        const SizedBox(height: 16),
                        _buildChartsCard(),
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

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: const BoxDecoration(
        color: Color(0xFF0F0F0F),
        border: Border(bottom: BorderSide(color: Color(0xFF1A1A1A))),
      ),
      child: Row(
        children: [
          Builder(builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          )),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('SMART TRASH', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Row(children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    color: _isReallyConnected ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(_isReallyConnected ? status : 'Offline', style: const TextStyle(color: Colors.white70)),
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

  Widget _buildModernSidebar() {
    return Drawer(
      backgroundColor: const Color(0xFF0A0A0A),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF16A34A).withOpacity(0.2),
                  const Color(0xFF0A0A0A),
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Icon(Icons.delete_outline, size: 48, color: Color(0xFF16A34A)),
                SizedBox(height: 16),
                Text('SMART TRASH', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
                SizedBox(height: 4),
                Text('Monitoring System', style: TextStyle(color: Colors.white60, fontSize: 14)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _modernMenuTile(Icons.dashboard_rounded, 'Dashboard', true, () {
                  if (Navigator.canPop(context)) {
                    Navigator.pop(context);
                  }
                  if (ModalRoute.of(context)?.settings.name != '/') {
                    Navigator.popUntil(context, (route) => route.isFirst);
                  }
                }),
                _modernMenuTile(Icons.history_rounded, 'Log Riwayat', false, () {
                  Navigator.pop(context);
                  Navigator.push(context, _createSlideRoute(const LogHistoryScreen()));
                }),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Divider(color: Colors.white10, height: 1),
                ),
                _modernMenuTile(Icons.info_outline_rounded, 'Tentang Device', false, () {
                  Navigator.pop(context);
                  _showAboutDialog();
                }),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF121212),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    color: _isReallyConnected ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Text(_isReallyConnected ? 'System Online' : 'System Offline',
                    style: const TextStyle(fontSize: 12, color: Colors.white70)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Route _createSlideRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (ctx, anim, secAnim) => page,
      transitionDuration: const Duration(milliseconds: 350),
      transitionsBuilder: (ctx, anim, secAnim, child) {
        return SlideTransition(
          position: Tween(begin: const Offset(1.0, 0.0), end: Offset.zero)
              .chain(CurveTween(curve: Curves.easeInOutCubic))
              .animate(anim),
          child: child,
        );
      },
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF121212),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Smart Trash Monitor'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('Version: 1.0', style: TextStyle(fontSize: 14)),
            SizedBox(height: 8),
            Text('Monitoring tempat sampah cerdas\ndengan sensor gas dan ultrasonik', style: TextStyle(fontSize: 13)),
            SizedBox(height: 16),
            Text('Device ID: TRASH-001', style: TextStyle(color: Colors.white70, fontSize: 12)),
            Text('Location: Main Building', style: TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(color: Color(0xFF16A34A))),
          ),
        ],
      ),
    );
  }

  Widget _modernMenuTile(IconData icon, String title, bool isActive, VoidCallback onTap) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOutCubic,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFF16A34A).withOpacity(0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive ? const Color(0xFF16A34A).withOpacity(0.3) : Colors.transparent,
        ),
      ),
      child: ListTile(
        leading: Icon(icon, color: isActive ? const Color(0xFF16A34A) : Colors.white60, size: 22),
        title: Text(title, style: TextStyle(
          color: isActive ? const Color(0xFF16A34A) : Colors.white,
          fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
          fontSize: 14,
        )),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildStatusCardsGrid() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _miniCard('FILL LEVEL', '${fillLevel.toStringAsFixed(0)}%', _fillStatusText(), _fillColor())),
            const SizedBox(width: 12),
            Expanded(child: _miniCard('GAS LEVEL', '${gasLevel.toStringAsFixed(0)}', _gasStatusText(), _gasColor())),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _miniCard('LID STATUS', servoOpen ? 'OPEN' : 'CLOSED', 'COUNT: $openCount x',
                servoOpen ? const Color(0xFFFB923C) : const Color(0xFF3B82F6))),
            const SizedBox(width: 12),
            Expanded(child: _miniCard('CONNECTION', _isReallyConnected ? 'ONLINE' : 'OFFLINE',
                _isReallyConnected ? 'ACTIVE' : 'NO DATA',
                _isReallyConnected ? const Color(0xFF16A34A) : const Color(0xFFDC2626))),
          ],
        ),
      ],
    );
  }

  Widget _buildStatusCardsRow() {
    return Row(
      children: [
        Expanded(child: _miniCard('FILL LEVEL', '${fillLevel.toStringAsFixed(0)}%', _fillStatusText(), _fillColor())),
        const SizedBox(width: 12),
        Expanded(child: _miniCard('GAS LEVEL', '${gasLevel.toStringAsFixed(0)}', _gasStatusText(), _gasColor())),
        const SizedBox(width: 12),
        Expanded(child: _miniCard('LID STATUS', servoOpen ? 'OPEN' : 'CLOSED', 'COUNT: $openCount x',
            servoOpen ? const Color(0xFFFB923C) : const Color(0xFF3B82F6))),
        const SizedBox(width: 12),
        Expanded(child: _miniCard('CONNECTION', _isReallyConnected ? 'ONLINE' : 'OFFLINE',
            _isReallyConnected ? 'ACTIVE' : 'NO DATA',
            _isReallyConnected ? const Color(0xFF16A34A) : const Color(0xFFDC2626))),
      ],
    );
  }

  Widget _miniCard(String label, String value, String statusText, Color accent) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.6))),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: accent)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: accent.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
            child: Text(statusText, style: TextStyle(color: accent, fontWeight: FontWeight.w700, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _buildTrashCapacityCard() {
    final fillColor = _fillColor();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('TRASH CAPACITY', style: TextStyle(color: Colors.white.withOpacity(0.6), fontWeight: FontWeight.w700)),
          const SizedBox(height: 18),
          Center(
            child: Container(
              width: 220, height: 340,
              decoration: BoxDecoration(
                color: const Color(0xFF0A0A0A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10, width: 2),
              ),
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeInOut,
                      width: double.infinity,
                      height: (fillLevel / 100) * 340,
                      decoration: BoxDecoration(
                        color: fillColor,
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
                      ),
                    ),
                  ),
                  Center(child: Text('${fillLevel.toStringAsFixed(0)}%',
                      style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w900, color: Colors.white54))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: fillLevel / 100, minHeight: 8,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation(fillColor),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Current Level', style: TextStyle(color: Colors.white.withOpacity(0.5))),
              Text('${fillLevel.toStringAsFixed(1)}%', style: TextStyle(color: fillColor, fontWeight: FontWeight.w700)),
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
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('GAS MONITOR', style: TextStyle(color: Colors.white.withOpacity(0.6), fontWeight: FontWeight.w700)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: gasColor.withOpacity(0.14), borderRadius: BorderRadius.circular(8)),
                child: Text(_gasStatusText(), style: TextStyle(color: gasColor, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: gasColor.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.air, color: gasColor),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Current Reading', style: TextStyle(color: Colors.white.withOpacity(0.6))),
                  const SizedBox(height: 6),
                  Text('${gasLevel.toStringAsFixed(0)} ppm',
                      style: TextStyle(color: gasColor, fontWeight: FontWeight.w900, fontSize: 28)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: gasLevel / 500, minHeight: 8,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation(gasColor),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('0 ppm', style: TextStyle(color: Colors.white.withOpacity(0.4))),
              Text('500 ppm', style: TextStyle(color: Colors.white.withOpacity(0.4))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChartsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('REALTIME MONITORING', style: TextStyle(color: Colors.white.withOpacity(0.6), fontWeight: FontWeight.w700)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF16A34A).withOpacity(0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFF16A34A), shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    const Text('LIVE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF16A34A))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          _buildMiniChart('Fill Level History', fillHistory, _fillColor(), 100),
          const SizedBox(height: 24),
          _buildMiniChart('Gas Level History', gasHistory, _gasColor(), 500),
          
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0A0A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              children: [
                _compactInfoRow(Icons.schedule, 'Last Update', lastUpdate),
                const Divider(color: Colors.white10, height: 20),
                _compactInfoRow(Icons.location_on_outlined, 'Location', 'Main Building'),
                const Divider(color: Colors.white10, height: 20),
                _compactInfoRow(Icons.sensors, 'Device ID', 'TRASH-001'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniChart(String title, List<FlSpot> data, Color color, double maxY) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        SizedBox(
          height: 120,
          child: data.isEmpty 
            ? Center(child: Text('Waiting for data...', style: TextStyle(color: Colors.white.withOpacity(0.3))))
            : LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: maxY / 4,
                    getDrawingHorizontalLine: (value) => FlLine(color: Colors.white10, strokeWidth: 1),
                  ),
                  titlesData: FlTitlesData(show: false),
                  borderData: FlBorderData(show: false),
                  minX: 0,
                  maxX: 14,
                  minY: 0,
                  maxY: maxY,
                  lineBarsData: [
                    LineChartBarData(
                      spots: data,
                      isCurved: true,
                      color: color,
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: color.withOpacity(0.1),
                      ),
                    ),
                  ],
                ),
              ),
        ),
      ],
    );
  }

  Widget _compactInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: Colors.white38, size: 16),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13)),
        const Spacer(),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
      ],
    );
  }
}