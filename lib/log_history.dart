import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';

class LogHistoryScreen extends StatefulWidget {
  const LogHistoryScreen({super.key});

  @override
  State<LogHistoryScreen> createState() => _LogHistoryScreenState();
}

class _LogHistoryScreenState extends State<LogHistoryScreen> {
  final DatabaseReference _logsRef = FirebaseDatabase.instance.ref('trashbin_logs');
  final DatabaseReference _trashRef = FirebaseDatabase.instance.ref('trashbin');
  
  List<LogEntry> allLogs = [];
  List<DailySummary> dailySummaries = [];
  bool isLoading = true;
  String selectedFilter = 'Harian';
  
  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  String _formatDate(DateTime date, {bool isToday = false}) {
    if (isToday) return 'Hari Ini';
    
    const days = ['Minggu', 'Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
    
    final dayName = days[date.weekday % 7];
    final monthName = months[date.month - 1];
    
    return '$dayName, ${date.day} $monthName ${date.year}';
  }

  Future<void> _loadLogs() async {
    setState(() => isLoading = true);
    
    try {
      final logsSnapshot = await _logsRef.get();
      final trashSnapshot = await _trashRef.get();
      
      List<LogEntry> logs = [];
      
      if (logsSnapshot.exists) {
        final data = Map<String, dynamic>.from(logsSnapshot.value as Map);
        data.forEach((key, value) {
          try {
            final logData = Map<String, dynamic>.from(value as Map);
            logs.add(LogEntry(
              id: key,
              timestamp: DateTime.parse(logData['timestamp']),
              event: logData['event'] ?? 'Unknown event',
              openCount: logData['open_count'] ?? 0,
            ));
          } catch (e) {
            debugPrint('Error parsing log: $e');
          }
        });
      }
      
      logs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      
      Map<String, dynamic>? currentData;
      if (trashSnapshot.exists) {
        currentData = Map<String, dynamic>.from(trashSnapshot.value as Map);
      }
      
      setState(() {
        allLogs = logs;
        dailySummaries = _generateDailySummaries(logs, currentData);
        isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading logs: $e');
      setState(() => isLoading = false);
    }
  }

  List<DailySummary> _generateDailySummaries(List<LogEntry> logs, Map<String, dynamic>? currentData) {
    Map<String, DailySummary> summaryMap = {};
    
    for (var log in logs) {
      final dateKey = DateFormat('yyyy-MM-dd').format(log.timestamp);
      
      if (!summaryMap.containsKey(dateKey)) {
        summaryMap[dateKey] = DailySummary(
          date: DateTime(log.timestamp.year, log.timestamp.month, log.timestamp.day),
          openCount: 0,
          events: [],
          avgGasLevel: 0,
          avgFillLevel: 0,
          maxGasLevel: 0,
          maxFillLevel: 0,
        );
      }
      
      summaryMap[dateKey]!.openCount++;
      summaryMap[dateKey]!.events.add(log);
    }
    
    if (currentData != null) {
      final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
      if (summaryMap.containsKey(todayKey)) {
        final gasLevel = double.tryParse(currentData['gas_level']?.toString() ?? '0') ?? 0;
        final fillLevel = double.tryParse(currentData['trash_percentage']?.toString() ?? '0') ?? 0;
        
        summaryMap[todayKey]!.avgGasLevel = gasLevel;
        summaryMap[todayKey]!.avgFillLevel = fillLevel;
        summaryMap[todayKey]!.maxGasLevel = gasLevel;
        summaryMap[todayKey]!.maxFillLevel = fillLevel;
      }
    }
    
    return summaryMap.values.toList()..sort((a, b) => b.date.compareTo(a.date));
  }

  List<DailySummary> get filteredSummaries {
    final now = DateTime.now();
    switch (selectedFilter) {
      case 'Harian':
        return dailySummaries.where((s) => s.date.isAfter(now.subtract(const Duration(days: 7)))).toList();
      case 'Mingguan':
        return dailySummaries.where((s) => s.date.isAfter(now.subtract(const Duration(days: 30)))).toList();
      case 'Bulanan':
        return dailySummaries.where((s) => s.date.isAfter(now.subtract(const Duration(days: 90)))).toList();
      default:
        return dailySummaries;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      drawer: _buildSidebar(),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildFilterTabs(),
            Expanded(
              child: isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF16A34A)))
                : filteredSummaries.isEmpty
                  ? _buildEmptyState()
                  : _buildSummaryList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar() {
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
                _modernMenuTile(Icons.dashboard_rounded, 'Dashboard', false, () {
                  Navigator.pop(context);
                  Navigator.pop(context);
                }),
                _modernMenuTile(Icons.history_rounded, 'Log Riwayat', true, () => Navigator.pop(context)),
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
        border: Border.all(color: isActive ? const Color(0xFF16A34A).withOpacity(0.3) : Colors.transparent),
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
            Text('Monitoring tempat sampah cerdas', style: TextStyle(fontSize: 13)),
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

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: const BoxDecoration(
        color: Color(0xFF0F0F0F),
        border: Border(bottom: BorderSide(color: Color(0xFF1A1A1A))),
      ),
      child: Row(
        children: [
          Builder(builder: (ctx) {
            return Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(8),
              ),
              child: IconButton(
                icon: const Icon(Icons.menu, color: Colors.white),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            );
          }),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('LOG RIWAYAT', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              SizedBox(height: 4),
              Text('Riwayat Aktivitas Sistem', style: TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
          const Spacer(),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(8),
            ),
            child: IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: _loadLogs,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTabs() {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          _filterTab('Harian'),
          _filterTab('Mingguan'),
          _filterTab('Bulanan'),
        ],
      ),
    );
  }

  Widget _filterTab(String label) {
    final isSelected = selectedFilter == label;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => selectedFilter = label),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF16A34A) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label, textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white60,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history, size: 64, color: Colors.white.withOpacity(0.3)),
          const SizedBox(height: 16),
          Text('Belum ada log aktivitas', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildSummaryList() {
    return RefreshIndicator(
      onRefresh: _loadLogs,
      color: const Color(0xFF16A34A),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: filteredSummaries.length,
        itemBuilder: (context, index) => _buildSummaryCard(filteredSummaries[index]),
      ),
    );
  }

  Widget _buildSummaryCard(DailySummary summary) {
    final isToday = DateFormat('yyyy-MM-dd').format(summary.date) == DateFormat('yyyy-MM-dd').format(DateTime.now());
    final dateText = _formatDate(summary.date, isToday: isToday);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isToday ? const Color(0xFF16A34A).withOpacity(0.3) : Colors.white10,
          width: isToday ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showDetailDialog(summary),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16A34A).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.calendar_today, color: Color(0xFF16A34A), size: 20),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(dateText,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                          const SizedBox(height: 4),
                          Text('${summary.openCount} aktivitas',
                            style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.white38),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(color: Colors.white10, height: 1),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _miniStat(Icons.delete_outline, 'Fill Level', '${summary.avgFillLevel.toStringAsFixed(0)}%', const Color(0xFF3B82F6)),
                    const SizedBox(width: 16),
                    _miniStat(Icons.air, 'Gas Level', '${summary.avgGasLevel.toStringAsFixed(0)} ppm', const Color(0xFFFB923C)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniStat(IconData icon, String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF0A0A0A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10)),
                  const SizedBox(height: 2),
                  Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDetailDialog(DailySummary summary) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Color(0xFF0D0D0D),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                ),
                Expanded(child: DetailView(
                  summary: summary,
                  scrollController: scrollController,
                  formatDate: _formatDate,
                )),
              ],
            ),
          );
        },
      ),
    );
  }
}

class DetailView extends StatelessWidget {
  final DailySummary summary;
  final ScrollController scrollController;
  final String Function(DateTime, {bool isToday}) formatDate;

  const DetailView({
    super.key,
    required this.summary,
    required this.scrollController,
    required this.formatDate,
  });

  @override
  Widget build(BuildContext context) {
    final isToday = DateFormat('yyyy-MM-dd').format(summary.date) == DateFormat('yyyy-MM-dd').format(DateTime.now());
    final dateText = formatDate(summary.date, isToday: isToday);
    
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(20),
      children: [
        Text(dateText,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white)),
        const SizedBox(height: 8),
        Text('Rekap Aktivitas Harian', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 14)),
        const SizedBox(height: 24),
        
        Row(
          children: [
            _statCard('Total Buka', '${summary.openCount}x', Icons.open_in_new, const Color(0xFF16A34A)),
            const SizedBox(width: 12),
            _statCard('Aktivitas', '${summary.events.length}', Icons.notifications_active, const Color(0xFF3B82F6)),
          ],
        ),
        
        const SizedBox(height: 24),
        _buildChartsSection(),
        const SizedBox(height: 24),
        _buildEventsTimeline(),
      ],
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF121212),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 12),
            Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: color)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildChartsSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.bar_chart, color: Color(0xFF16A34A), size: 20),
              SizedBox(width: 8),
              Text('Statistik Harian', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
            ],
          ),
          const SizedBox(height: 20),
          _buildSimpleBarChart('Fill Level', summary.avgFillLevel, 100, const Color(0xFF3B82F6)),
          const SizedBox(height: 16),
          _buildSimpleBarChart('Gas Level', summary.avgGasLevel, 500, const Color(0xFFFB923C)),
        ],
      ),
    );
  }

  Widget _buildSimpleBarChart(String label, double value, double max, Color color) {
    final percentage = (value / max).clamp(0.0, 1.0);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13, fontWeight: FontWeight.w600)),
            Text(label.contains('Fill') ? '${value.toStringAsFixed(0)}%' : '${value.toStringAsFixed(0)} ppm',
              style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 8),
        Stack(
          children: [
            Container(height: 8, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(4))),
            FractionallySizedBox(
              widthFactor: percentage,
              child: Container(height: 8, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEventsTimeline() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.timeline, color: Color(0xFF16A34A), size: 20),
              SizedBox(width: 8),
              Text('Timeline Aktivitas', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
            ],
          ),
          const SizedBox(height: 16),
          ...summary.events.take(10).map((event) => _buildTimelineItem(event)),
          if (summary.events.length > 10)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('+ ${summary.events.length - 10} aktivitas lainnya',
                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12, fontStyle: FontStyle.italic)),
            ),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(LogEntry event) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF16A34A), shape: BoxShape.circle)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.event, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(DateFormat('HH:mm:ss').format(event.timestamp),
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class LogEntry {
  final String id;
  final DateTime timestamp;
  final String event;
  final int openCount;

  LogEntry({required this.id, required this.timestamp, required this.event, required this.openCount});
}

class DailySummary {
  final DateTime date;
  int openCount;
  final List<LogEntry> events;
  double avgGasLevel;
  double avgFillLevel;
  double maxGasLevel;
  double maxFillLevel;

  DailySummary({
    required this.date,
    required this.openCount,
    required this.events,
    required this.avgGasLevel,
    required this.avgFillLevel,
    required this.maxGasLevel,
    required this.maxFillLevel,
  });
}