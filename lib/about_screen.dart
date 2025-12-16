import 'package:flutter/material.dart';

class AboutScreen extends StatelessWidget {
  final bool isDarkMode;
  
  const AboutScreen({super.key, this.isDarkMode = true});

  Color get _bgColor => isDarkMode ? const Color(0xFF0D0D0D) : const Color(0xFFF5F5F5);
  Color get _cardBg => isDarkMode ? const Color(0xFF121212) : Colors.white;
  Color get _headerBg => isDarkMode ? const Color(0xFF0F0F0F) : Colors.white;
  Color get _textPrimary => isDarkMode ? Colors.white : const Color(0xFF1A1A1A);
  Color get _textSecondary => isDarkMode ? Colors.white70 : const Color(0xFF6B7280);
  Color get _dividerColor => isDarkMode ? Colors.white10 : const Color(0xFFE5E7EB);
  Color get _accentBg => isDarkMode ? const Color(0xFF0A0A0A) : const Color(0xFFF3F4F6);

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth >= 900;
    
    return Scaffold(
      backgroundColor: _bgColor,
      drawer: _buildSidebar(context),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildAppInfo(isWide),
                    const SizedBox(height: 20),
                    _buildDescription(),
                    const SizedBox(height: 20),
                    _buildFeatures(),
                    const SizedBox(height: 20),
                    _buildComponents(),
                    const SizedBox(height: 20),
                    _buildTeam(),
                    const SizedBox(height: 20),
                    _buildVersion(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar(BuildContext context) {
    return Drawer(
      backgroundColor: isDarkMode ? const Color(0xFF0A0A0A) : Colors.white,
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
                  isDarkMode ? const Color(0xFF0A0A0A) : Colors.white,
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
                _modernMenuTile(context, Icons.dashboard_rounded, 'Dashboard', false, () {
                  Navigator.pop(context); // Close drawer
                  Navigator.pop(context); // Go back to dashboard
                }),
                _modernMenuTile(context, Icons.history_rounded, 'Log Riwayat', false, () {
                  Navigator.pop(context); // Close drawer
                  // Don't pop again, just stay on this screen
                }),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Divider(color: Colors.white10, height: 1),
                ),
                _modernMenuTile(context, Icons.info_outline_rounded, 'Tentang Device', true, () {
                  Navigator.pop(context);
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _modernMenuTile(BuildContext context, IconData icon, String title, bool isActive, VoidCallback onTap) {
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

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: _headerBg,
        border: Border(bottom: BorderSide(color: _dividerColor)),
        boxShadow: isDarkMode ? [] : [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Builder(builder: (ctx) {
            return Container(
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF1A1A1A) : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: IconButton(
                icon: Icon(Icons.menu, color: _textPrimary),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            );
          }),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('TENTANG DEVICE', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _textPrimary)),
              const SizedBox(height: 4),
              Text('Informasi Aplikasi', style: TextStyle(color: _textSecondary, fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAppInfo(bool isWide) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isWide ? 32 : 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF16A34A), Color(0xFF15803D)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF16A34A).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.delete_outline, size: 64, color: Colors.white),
          ),
          const SizedBox(height: 20),
          const Text(
            'SMART TRASH MONITOR',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 1.2,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Sistem Monitoring Tempat Sampah Cerdas',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white70,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildDescription() {
    return _buildCard(
      title: 'Deskripsi Aplikasi',
      icon: Icons.description_outlined,
      child: Text(
        'Smart Trash Monitor adalah aplikasi monitoring real-time untuk tempat sampah pintar yang dilengkapi dengan sensor ultrasonik untuk mengukur tingkat penuhnya sampah dan sensor gas MQ-135 untuk mendeteksi bau tidak sedap. Aplikasi ini memungkinkan pengguna untuk memantau kondisi tempat sampah dari jarak jauh.',
        style: TextStyle(color: _textSecondary, height: 1.6, fontSize: 14),
      ),
    );
  }

  Widget _buildFeatures() {
    return _buildCard(
      title: 'Fitur Utama',
      icon: Icons.star_outline,
      child: Column(
        children: [
          _buildFeatureItem(Icons.speed, 'Monitoring Real-time', 'Pantau kondisi sampah secara langsung'),
          _buildFeatureItem(Icons.air, 'Deteksi Gas', 'Sensor MQ-135 untuk deteksi bau'),
          _buildFeatureItem(Icons.height, 'Level Sampah', 'Sensor ultrasonik HC-SR04'),
          _buildFeatureItem(Icons.history, 'Log Aktivitas', 'Riwayat lengkap semua aktivitas'),
          _buildFeatureItem(Icons.dark_mode, 'Dark/Light Theme', 'Tema dapat disesuaikan'),
          _buildFeatureItem(Icons.trending_up, 'Grafik Real-time', 'Visualisasi data sensor'),
        ],
      ),
    );
  }

  Widget _buildComponents() {
    return _buildCard(
      title: 'Komponen Hardware',
      icon: Icons.memory,
      child: Column(
        children: [
          _buildComponentItem('ESP32/ESP8266', 'Microcontroller utama', Icons.developer_board),
          const SizedBox(height: 12),
          _buildComponentItem('Sensor HC-SR04', 'Ultrasonik untuk tinggi sampah', Icons.straighten),
          const SizedBox(height: 12),
          _buildComponentItem('Sensor MQ-135', 'Deteksi gas dan bau', Icons.air),
          const SizedBox(height: 12),
          _buildComponentItem('Servo Motor SG90', 'Kontrol buka/tutup', Icons.settings_input_component),
          const SizedBox(height: 12),
          _buildComponentItem('Firebase Realtime DB', 'Cloud database', Icons.cloud),
        ],
      ),
    );
  }

  Widget _buildTeam() {
    return _buildCard(
      title: 'Tim Pengembang',
      icon: Icons.people_outline,
      child: Column(
        children: [
          _buildTeamMember('IoT Team', 'Full-Stack Developer', Icons.code),
          const SizedBox(height: 16),
          _buildTeamMember('IoT Team', 'Hardware Engineer', Icons.hardware),
          const SizedBox(height: 16),
          _buildTeamMember('Design Team', 'UI/UX Designer', Icons.palette),
        ],
      ),
    );
  } 

  Widget _buildVersion() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _dividerColor),
        boxShadow: isDarkMode ? [] : [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Version', style: TextStyle(color: _textSecondary)),
              Text('1.0.0', style: TextStyle(color: _textPrimary, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Device ID', style: TextStyle(color: _textSecondary)),
              Text('TRASH-001', style: TextStyle(color: _textPrimary, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Build Date', style: TextStyle(color: _textSecondary)),
              Text('December 2025', style: TextStyle(color: _textPrimary, fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCard({required String title, required IconData icon, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _dividerColor),
        boxShadow: isDarkMode ? [] : [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF16A34A), size: 24),
              const SizedBox(width: 12),
              Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _textPrimary)),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildFeatureItem(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF16A34A).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: const Color(0xFF16A34A), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: _textPrimary, fontSize: 14)),
                Text(subtitle, style: TextStyle(color: _textSecondary, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComponentItem(String name, String description, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _accentBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _dividerColor),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF3B82F6), size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: TextStyle(fontWeight: FontWeight.w700, color: _textPrimary, fontSize: 14)),
                Text(description, style: TextStyle(color: _textSecondary, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTeamMember(String name, String role, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF3B82F6).withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _textPrimary)),
              Text(role, style: TextStyle(color: _textSecondary, fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }
}