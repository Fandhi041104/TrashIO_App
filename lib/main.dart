import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'log_history.dart';
import 'about_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const SmartTrashApp());
}

class SmartTrashApp extends StatefulWidget {
  const SmartTrashApp({super.key});

  @override
  State<SmartTrashApp> createState() => _SmartTrashAppState();
}

class _SmartTrashAppState extends State<SmartTrashApp> {
  bool isDarkMode = true;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      isDarkMode = prefs.getBool('isDarkMode') ?? true;
    });
  }

  Future<void> _toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      isDarkMode = !isDarkMode;
      prefs.setBool('isDarkMode', isDarkMode);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Trash Monitor',
      debugShowCheckedModeBanner: false,
      theme: isDarkMode ? _darkTheme() : _lightTheme(),
      home: TrashMonitorScreen(
        isDarkMode: isDarkMode,
        onThemeToggle: _toggleTheme,
      ),
    );
  }

  ThemeData _darkTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF0D0D0D),
      fontFamily: 'Inter',
      primaryColor: const Color(0xFF16A34A),
    );
  }

  ThemeData _lightTheme() {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF5F5F5),
      fontFamily: 'Inter',
      primaryColor: const Color(0xFF16A34A),
    );
  }
}

class ChartData {
  final DateTime time;
  final double value;
  ChartData(this.time, this.value);
}

class TrashMonitorScreen extends StatefulWidget {
  final bool isDarkMode;
  final VoidCallback onThemeToggle;

  const TrashMonitorScreen({
    super.key,
    required this.isDarkMode,
    required this.onThemeToggle,
  });

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
  bool isControlling = false;
  
  List<FlSpot> fillHistory = [];
  List<FlSpot> gasHistory = [];
  DateTime? lastChartUpdate;

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
        
        // Trigger warnings
        _checkWarnings();
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

  void _checkWarnings() {
    // Warning for gas level
    if (gasLevel >= 250 && gasLevel < 350) {
      _showWarning(
        'Peringatan Gas!',
        'Tempat sampah bau terdeteksi. Segera cek/buang sampah!',
        Icons.air,
        const Color(0xFFFB923C),
      );
    } else if (gasLevel >= 350) {
      _showWarning(
        'Bahaya Gas!',
        'Gas berbahaya terdeteksi! Segera buang sampah!',
        Icons.warning,
        const Color(0xFFDC2626),
      );
    }

    // Warning for fill level
    if (fillLevel >= 90) {
      _showWarning(
        'Sampah Penuh!',
        'Tempat sampah sudah penuh (${fillLevel.toStringAsFixed(0)}%). Segera buang sampah!',
        Icons.delete,
        const Color(0xFFDC2626),
      );
    } else if (fillLevel >= 80) {
      _showWarning(
        'Hampir Penuh!',
        'Tempat sampah hampir penuh (${fillLevel.toStringAsFixed(0)}%). Harap segera dikosongkan.',
        Icons.delete_outline,
        const Color(0xFFFB923C),
      );
    }
  }

  void _showWarning(String title, String message, IconData icon, Color color) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(message, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: color,
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _controlServo(bool open) async {
    if (isControlling || !_isReallyConnected) return;

    setState(() => isControlling = true);

    try {
      await _trashRef.update({
        'servo_open': open,
        'last_update': DateTime.now().millisecondsSinceEpoch.toString(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(open ? 'Membuka tutup sampah...' : 'Menutup tutup sampah...'),
            backgroundColor: const Color(0xFF16A34A),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isControlling = false);
      }
    }
  }

  void _updateChartData() {
    final now = DateTime.now();
    
    // Update hanya setiap 1 menit
    if (lastChartUpdate != null && now.difference(lastChartUpdate!).inSeconds < 60) {
      return;
    }
    
    lastChartUpdate = now;
    
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

  Color get _bgColor => widget.isDarkMode ? const Color(0xFF0D0D0D) : const Color(0xFFF5F5F5);
  Color get _cardBg => widget.isDarkMode ? const Color(0xFF121212) : Colors.white;
  Color get _headerBg => widget.isDarkMode ? const Color(0xFF0F0F0F) : Colors.white;
  Color get _textPrimary => widget.isDarkMode ? Colors.white : const Color(0xFF1A1A1A);
  Color get _textSecondary => widget.isDarkMode ? Colors.white70 : const Color(0xFF6B7280);
  Color get _dividerColor => widget.isDarkMode ? Colors.white10 : const Color(0xFFE5E7EB);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      drawer: _buildModernSidebar(),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _onRefresh,
          color: const Color(0xFF16A34A),
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
                        _buildControlCard(),
                        const SizedBox(height: 16),
                        // Row untuk Trash Capacity + Charts (Desktop/Wide)
                        isWide ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 2,
                              child: _buildTrashCapacityCard(),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 3,
                              child: _buildChartsCard(),
                            ),
                          ],
                        ) : Column(
                          children: [
                            _buildTrashCapacityCard(),
                            const SizedBox(height: 16),
                            _buildChartsCard(),
                          ],
                        ),
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

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: _headerBg,
        border: Border(bottom: BorderSide(color: _dividerColor)),
        boxShadow: widget.isDarkMode ? [] : [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Builder(builder: (ctx) => IconButton(
            icon: Icon(Icons.menu, color: _textPrimary),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          )),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('SMART TRASH', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _textPrimary)),
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
                Text(_isReallyConnected ? status : 'Offline', style: TextStyle(color: _textSecondary)),
              ]),
            ],
          ),
          const Spacer(),
          IconButton(
            icon: Icon(
              widget.isDarkMode ? Icons.light_mode : Icons.dark_mode,
              color: _textPrimary,
            ),
            onPressed: widget.onThemeToggle,
            tooltip: widget.isDarkMode ? 'Mode Terang' : 'Mode Gelap',
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              color: widget.isDarkMode ? const Color(0xFF1A1A1A) : const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: IconButton(
              icon: Icon(Icons.refresh, color: _textPrimary),
              onPressed: _onRefresh,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernSidebar() {
    return Drawer(
      backgroundColor: widget.isDarkMode ? const Color(0xFF0A0A0A) : Colors.white,
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
                  widget.isDarkMode ? const Color(0xFF0A0A0A) : Colors.white,
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.delete_outline, size: 48, color: Color(0xFF16A34A)),
                const SizedBox(height: 16),
                Text('SMART TRASH', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 1.2, color: _textPrimary)),
                const SizedBox(height: 4),
                Text('Monitoring System', style: TextStyle(color: _textSecondary, fontSize: 14)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _modernMenuTile(Icons.dashboard_rounded, 'Dashboard', true, () {
                  if (Navigator.canPop(context)) Navigator.pop(context);
                }),
                _modernMenuTile(Icons.history_rounded, 'Log Riwayat', false, () {
                  Navigator.pop(context);
                  Navigator.push(context, _createSlideRoute(LogHistoryScreen(isDarkMode: widget.isDarkMode)));
                }),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Divider(color: _dividerColor, height: 1),
                ),
                _modernMenuTile(Icons.info_outline_rounded, 'Tentang Device', false, () {
                  Navigator.pop(context);
                  Navigator.push(context, _createSlideRoute(AboutScreen(isDarkMode: widget.isDarkMode)));
                }),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _dividerColor),
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
                    style: TextStyle(fontSize: 12, color: _textSecondary)),
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

  Widget _modernMenuTile(IconData icon, String title, bool isActive, VoidCallback onTap) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOutCubic,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFF16A34A).withOpacity(0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isActive ? const Color(0xFF16A34A).withOpacity(0.3) : Colors.transparent),
      ),
      child: ListTile(
        leading: Icon(icon, color: isActive ? const Color(0xFF16A34A) : _textSecondary, size: 22),
        title: Text(title, style: TextStyle(
          color: isActive ? const Color(0xFF16A34A) : _textPrimary,
          fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
          fontSize: 14,
        )),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildControlCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _dividerColor),
        boxShadow: widget.isDarkMode ? [] : [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF16A34A), Color(0xFF15803D)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.settings_remote, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text('KONTROL TUTUP SAMPAH',
                    style: TextStyle(color: _textPrimary, fontWeight: FontWeight.w700, fontSize: 15)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: servoOpen 
                      ? [const Color(0xFFFB923C), const Color(0xFFF59E0B)]
                      : [const Color(0xFF3B82F6), const Color(0xFF2563EB)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: (servoOpen ? const Color(0xFFFB923C) : const Color(0xFF3B82F6)).withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      servoOpen ? Icons.lock_open : Icons.lock,
                      color: Colors.white,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      servoOpen ? 'TERBUKA' : 'TERTUTUP',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: (_isReallyConnected && !servoOpen && !isControlling)
                        ? const LinearGradient(
                            colors: [Color(0xFF16A34A), Color(0xFF15803D)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: (_isReallyConnected && !servoOpen && !isControlling)
                        ? null
                        : widget.isDarkMode ? const Color(0xFF1A1A1A) : const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: (_isReallyConnected && !servoOpen && !isControlling) ? [
                      BoxShadow(
                        color: const Color(0xFF16A34A).withOpacity(0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ] : [],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: (_isReallyConnected && !servoOpen && !isControlling)
                          ? () => _controlServo(true)
                          : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isControlling ? Icons.hourglass_empty : Icons.lock_open_rounded,
                              color: (_isReallyConnected && !servoOpen && !isControlling)
                                  ? Colors.white
                                  : _textSecondary,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              isControlling ? 'Memproses...' : 'Buka Tutup',
                              style: TextStyle(
                                color: (_isReallyConnected && !servoOpen && !isControlling)
                                    ? Colors.white
                                    : _textSecondary,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: (_isReallyConnected && servoOpen && !isControlling)
                        ? const LinearGradient(
                            colors: [Color(0xFFDC2626), Color(0xFFB91C1C)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: (_isReallyConnected && servoOpen && !isControlling)
                        ? null
                        : widget.isDarkMode ? const Color(0xFF1A1A1A) : const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: (_isReallyConnected && servoOpen && !isControlling) ? [
                      BoxShadow(
                        color: const Color(0xFFDC2626).withOpacity(0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ] : [],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: (_isReallyConnected && servoOpen && !isControlling)
                          ? () => _controlServo(false)
                          : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isControlling ? Icons.hourglass_empty : Icons.lock_rounded,
                              color: (_isReallyConnected && servoOpen && !isControlling)
                                  ? Colors.white
                                  : _textSecondary,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              isControlling ? 'Memproses...' : 'Tutup',
                              style: TextStyle(
                                color: (_isReallyConnected && servoOpen && !isControlling)
                                    ? Colors.white
                                    : _textSecondary,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (!_isReallyConnected)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFDC2626).withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_rounded, color: Color(0xFFDC2626), size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Kontrol tidak tersedia. Sistem offline.',
                        style: TextStyle(
                          color: widget.isDarkMode ? Colors.white : const Color(0xFFDC2626),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
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
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withOpacity(widget.isDarkMode ? 0.15 : 0.08),
            _cardBg,
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withOpacity(0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(widget.isDarkMode ? 0.2 : 0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: _textSecondary)),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: accent)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
            ),
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
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _dividerColor),
        boxShadow: widget.isDarkMode ? [] : [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('TRASH CAPACITY', style: TextStyle(color: _textSecondary, fontWeight: FontWeight.w700)),
          const SizedBox(height: 18),
          Center(
            child: Container(
              width: 140,
              height: 220,
              decoration: BoxDecoration(
                color: widget.isDarkMode ? const Color(0xFF0A0A0A) : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _dividerColor, width: 2),
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
                      height: (fillLevel / 100) * 220,
                      decoration: BoxDecoration(
                        color: fillColor,
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
                      ),
                    ),
                  ),
                  Center(child: Text('${fillLevel.toStringAsFixed(0)}%',
                      style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, 
                          color: widget.isDarkMode ? Colors.white54 : Colors.black38))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: fillLevel / 100, minHeight: 8,
              backgroundColor: _dividerColor,
              valueColor: AlwaysStoppedAnimation(fillColor),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Current Level', style: TextStyle(color: _textSecondary, fontSize: 12)),
              Text('${fillLevel.toStringAsFixed(1)}%', style: TextStyle(color: fillColor, fontWeight: FontWeight.w700)),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildChartsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _dividerColor),
        boxShadow: widget.isDarkMode ? [] : [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('REALTIME MONITORING', style: TextStyle(color: _textSecondary, fontWeight: FontWeight.w700)),
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
        ],
      ),
    );
  }

  Widget _buildDeviceInfoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _dividerColor),
        boxShadow: widget.isDarkMode ? [] : [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('DEVICE INFO', style: TextStyle(color: _textSecondary, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          _compactInfoRow(Icons.schedule, 'Last Update', lastUpdate),
          Divider(color: _dividerColor, height: 24),
          _compactInfoRow(Icons.location_on_outlined, 'Location', 'Main Building'),
          Divider(color: _dividerColor, height: 24),
          _compactInfoRow(Icons.sensors, 'Device ID', 'TRASH-001'),
        ],
      ),
    );
  }

  Widget _buildMiniChart(String title, List<FlSpot> data, Color color, double maxY) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(color: _textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        SizedBox(
          height: 120,
          child: data.isEmpty 
            ? Center(child: Text('Waiting for data...', style: TextStyle(color: _textSecondary)))
            : LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: maxY / 4,
                    getDrawingHorizontalLine: (value) => FlLine(color: _dividerColor, strokeWidth: 1),
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
                      belowBarData: BarAreaData(show: true, color: color.withOpacity(0.1)),
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
        Icon(icon, color: _textSecondary, size: 16),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(color: _textSecondary, fontSize: 13)),
        const Spacer(),
        Text(value, style: TextStyle(color: _textPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
      ],
    );
  }
}