import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';

import 'about_screen.dart';

class LogHistoryScreen extends StatefulWidget {
  final bool isDarkMode;
  
  const LogHistoryScreen({super.key, this.isDarkMode = true});

  @override
  State<LogHistoryScreen> createState() => _LogHistoryScreenState();
}

class _LogHistoryScreenState extends State<LogHistoryScreen> {
  final DatabaseReference _logsRef = FirebaseDatabase.instance.ref('trashbin_logs');
  final DatabaseReference _trashRef = FirebaseDatabase.instance.ref('trashbin');
  
  List<DailySummary> allSummaries = [];
  bool isLoading = true;
  int currentPage = 0;
  final int itemsPerPage = 10;
  DateTime? selectedDate;
  String filterMode = 'all';
  int? selectedMonth;
  int? selectedYear;
  
  Color get _bgColor => widget.isDarkMode ? const Color(0xFF0D0D0D) : const Color(0xFFF5F5F5);
  Color get _cardBg => widget.isDarkMode ? const Color(0xFF121212) : Colors.white;
  Color get _headerBg => widget.isDarkMode ? const Color(0xFF0F0F0F) : Colors.white;
  Color get _textPrimary => widget.isDarkMode ? Colors.white : const Color(0xFF1A1A1A);
  Color get _textSecondary => widget.isDarkMode ? Colors.white70 : const Color(0xFF6B7280);
  Color get _dividerColor => widget.isDarkMode ? Colors.white10 : const Color(0xFFE5E7EB);

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
        allSummaries = _generateDailySummaries(logs, currentData);
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
    if (filterMode == 'day' && selectedDate != null) {
      return allSummaries.where((s) => 
        DateFormat('yyyy-MM-dd').format(s.date) == DateFormat('yyyy-MM-dd').format(selectedDate!)
      ).toList();
    } else if (filterMode == 'month' && selectedMonth != null && selectedYear != null) {
      return allSummaries.where((s) => 
        s.date.month == selectedMonth && s.date.year == selectedYear
      ).toList();
    } else if (filterMode == 'year' && selectedYear != null) {
      return allSummaries.where((s) => s.date.year == selectedYear).toList();
    }
    return allSummaries;
  }

  String get filterText {
    if (filterMode == 'day' && selectedDate != null) {
      return _formatDate(selectedDate!);
    } else if (filterMode == 'month' && selectedMonth != null && selectedYear != null) {
      const months = ['Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 
                      'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'];
      return '${months[selectedMonth! - 1]} $selectedYear';
    } else if (filterMode == 'year' && selectedYear != null) {
      return 'Tahun $selectedYear';
    }
    return '${filteredSummaries.length} hari tercatat';
  }

  List<DailySummary> get paginatedSummaries {
    final filtered = filteredSummaries;
    final start = currentPage * itemsPerPage;
    final end = (start + itemsPerPage).clamp(0, filtered.length);
    return filtered.sublist(start, end);
  }

  int get totalPages => (filteredSummaries.length / itemsPerPage).ceil();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      drawer: _buildSidebar(),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF16A34A)))
                : filteredSummaries.isEmpty
                  ? _buildEmptyState()
                  : Column(
                      children: [
                        Expanded(child: _buildSummaryList()),
                        if (totalPages > 1) _buildPagination(),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar() {
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
                  Navigator.push(context, PageRouteBuilder(
                    pageBuilder: (ctx, anim, secAnim) => AboutScreen(isDarkMode: widget.isDarkMode),
                    transitionDuration: const Duration(milliseconds: 350),
                    transitionsBuilder: (ctx, anim, secAnim, child) {
                      return SlideTransition(
                        position: Tween(begin: const Offset(1.0, 0.0), end: Offset.zero)
                            .chain(CurveTween(curve: Curves.easeInOutCubic))
                            .animate(anim),
                        child: child,
                      );
                    },
                  ));
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
          Builder(builder: (ctx) {
            return Container(
              decoration: BoxDecoration(
                color: widget.isDarkMode ? const Color(0xFF1A1A1A) : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: IconButton(
                icon: Icon(Icons.menu, color: _textPrimary),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            );
          }),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('LOG RIWAYAT', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _textPrimary)),
                const SizedBox(height: 4),
                Text(filterText, 
                  style: TextStyle(color: _textSecondary, fontSize: 13)),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
              ),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF3B82F6).withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: IconButton(
              icon: const Icon(Icons.calendar_today, color: Colors.white, size: 20),
              onPressed: _showFilterDialog,
              tooltip: 'Filter Tanggal',
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              color: widget.isDarkMode ? const Color(0xFF1A1A1A) : const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: IconButton(
              icon: Icon(Icons.refresh, color: _textPrimary),
              onPressed: _loadLogs,
            ),
          ),
        ],
      ),
    );
  }

  void _resetFilter() {
    setState(() {
      filterMode = 'all';
      selectedDate = null;
      selectedMonth = null;
      selectedYear = null;
      currentPage = 0;
    });
  }

  Future<void> _showFilterDialog() async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Filter Log', style: TextStyle(color: _textPrimary, fontWeight: FontWeight.w800)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _filterButton(
                icon: Icons.today,
                label: 'Hari Ini',
                onTap: () {
                  setState(() {
                    filterMode = 'day';
                    selectedDate = DateTime.now();
                    selectedMonth = null;
                    selectedYear = null;
                    currentPage = 0;
                  });
                  Navigator.pop(context);
                },
              ),
              const SizedBox(height: 8),
              _filterButton(
                icon: Icons.calendar_month,
                label: 'Pilih Tanggal',
                onTap: () async {
                  Navigator.pop(context);
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2023),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    setState(() {
                      filterMode = 'day';
                      selectedDate = picked;
                      selectedMonth = null;
                      selectedYear = null;
                      currentPage = 0;
                    });
                  }
                },
              ),
              const SizedBox(height: 8),
              _filterButton(
                icon: Icons.calendar_view_month,
                label: 'Bulan Ini',
                onTap: () {
                  final now = DateTime.now();
                  setState(() {
                    filterMode = 'month';
                    selectedDate = null;
                    selectedMonth = now.month;
                    selectedYear = now.year;
                    currentPage = 0;
                  });
                  Navigator.pop(context);
                },
              ),
              const SizedBox(height: 8),
              _filterButton(
                icon: Icons.event,
                label: 'Tahun Ini',
                onTap: () {
                  final now = DateTime.now();
                  setState(() {
                    filterMode = 'year';
                    selectedDate = null;
                    selectedMonth = null;
                    selectedYear = now.year;
                    currentPage = 0;
                  });
                  Navigator.pop(context);
                },
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  _resetFilter();
                  Navigator.pop(context);
                },
                child: const Text(
                  'Reset Filter',
                  style: TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: widget.isDarkMode ? const Color(0xFF0A0A0A) : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(icon, color: const Color(0xFF16A34A)),
                const SizedBox(width: 12),
                Text(label, style: TextStyle(color: _textPrimary, fontWeight: FontWeight.w600)),
              ],
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
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF3B82F6).withOpacity(0.1),
                  const Color(0xFF2563EB).withOpacity(0.05),
                ],
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.event_busy, size: 64, color: _textSecondary),
          ),
          const SizedBox(height: 24),
          Text('Tidak Ada Data', 
            style: TextStyle(
              color: _textPrimary, 
              fontSize: 20, 
              fontWeight: FontWeight.w700
            )),
          const SizedBox(height: 8),
          Text('Tidak ada log aktivitas untuk filter ini',
            style: TextStyle(color: _textSecondary, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          if (filterMode != 'all')
            ElevatedButton.icon(
              onPressed: _resetFilter,
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Kembali ke Semua Data'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSummaryList() {
    return RefreshIndicator(
      onRefresh: _loadLogs,
      color: const Color(0xFF16A34A),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        itemCount: paginatedSummaries.length,
        itemBuilder: (context, index) => _buildSummaryCard(paginatedSummaries[index]),
      ),
    );
  }

  Widget _buildSummaryCard(DailySummary summary) {
    final isToday = DateFormat('yyyy-MM-dd').format(summary.date) == DateFormat('yyyy-MM-dd').format(DateTime.now());
    final dateText = _formatDate(summary.date, isToday: isToday);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: isToday ? LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF16A34A).withOpacity(widget.isDarkMode ? 0.1 : 0.05),
            _cardBg,
          ],
        ) : null,
        color: isToday ? null : _cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isToday ? const Color(0xFF16A34A).withOpacity(0.5) : _dividerColor,
          width: isToday ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isToday 
              ? const Color(0xFF16A34A).withOpacity(widget.isDarkMode ? 0.2 : 0.1)
              : Colors.black.withOpacity(widget.isDarkMode ? 0 : 0.05),
            blurRadius: isToday ? 20 : 10,
            offset: Offset(0, isToday ? 8 : 4),
          ),
        ],
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
                        gradient: const LinearGradient(
                          colors: [Color(0xFF16A34A), Color(0xFF15803D)],
                        ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF16A34A).withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.calendar_today, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(dateText,
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _textPrimary)),
                          const SizedBox(height: 4),
                          Text('${summary.openCount} aktivitas',
                            style: TextStyle(color: _textSecondary, fontSize: 13)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.white38),
                  ],
                ),
                const SizedBox(height: 16),
                Divider(color: _dividerColor, height: 1),
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
          color: widget.isDarkMode ? const Color(0xFF0A0A0A) : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _dividerColor),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(color: _textSecondary, fontSize: 10)),
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

  Widget _buildPagination() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: _headerBg,
        border: Border(top: BorderSide(color: _dividerColor)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: currentPage > 0 ? () => setState(() => currentPage--) : null,
            icon: const Icon(Icons.chevron_left),
            color: _textPrimary,
          ),
          const SizedBox(width: 16),
          Text(
            'Page ${currentPage + 1} of $totalPages',
            style: TextStyle(color: _textPrimary, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 16),
          IconButton(
            onPressed: currentPage < totalPages - 1 ? () => setState(() => currentPage++) : null,
            icon: const Icon(Icons.chevron_right),
            color: _textPrimary,
          ),
        ],
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
            decoration: BoxDecoration(
              color: _bgColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: _dividerColor, borderRadius: BorderRadius.circular(2)),
                ),
                Expanded(child: DetailView(
                  summary: summary,
                  scrollController: scrollController,
                  formatDate: _formatDate,
                  isDarkMode: widget.isDarkMode,
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
  final bool isDarkMode;

  const DetailView({
    super.key,
    required this.summary,
    required this.scrollController,
    required this.formatDate,
    this.isDarkMode = true,
  });

  Color get _cardBg => isDarkMode ? const Color(0xFF121212) : Colors.white;
  Color get _textPrimary => isDarkMode ? Colors.white : const Color(0xFF1A1A1A);
  Color get _textSecondary => isDarkMode ? Colors.white70 : const Color(0xFF6B7280);
  Color get _dividerColor => isDarkMode ? Colors.white10 : const Color(0xFFE5E7EB);

  @override
  Widget build(BuildContext context) {
    final isToday = DateFormat('yyyy-MM-dd').format(summary.date) == DateFormat('yyyy-MM-dd').format(DateTime.now());
    final dateText = formatDate(summary.date, isToday: isToday);
    
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(20),
      children: [
        Text(dateText,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: _textPrimary)),
        const SizedBox(height: 8),
        Text('Rekap Aktivitas Harian', style: TextStyle(color: _textSecondary, fontSize: 14)),
        const SizedBox(height: 24),
        
        Row(
          children: [
            _statCard('Total Buka', '${summary.openCount}x', Icons.open_in_new, const Color(0xFF16A34A)),
            const SizedBox(width: 12),
            _statCard('Aktivitas', '${summary.events.length}', Icons.notifications_active, const Color(0xFF3B82F6)),
          ],
        ),
        
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
          color: _cardBg,
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
            Text(label, style: TextStyle(color: _textSecondary, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildEventsTimeline() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.timeline, color: Color(0xFF16A34A), size: 20),
              const SizedBox(width: 8),
              Text('Timeline Aktivitas', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _textPrimary)),
            ],
          ),
          const SizedBox(height: 16),
          ...summary.events.map((event) => _buildTimelineItem(event)),
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
                Text(event.event, style: TextStyle(color: _textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(DateFormat('HH:mm:ss').format(event.timestamp),
                  style: TextStyle(color: _textSecondary, fontSize: 11)),
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

  LogEntry({required this.id, required this.timestamp, required this.event});
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