import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

class LogHistoryScreen extends StatefulWidget {
  const LogHistoryScreen({super.key});

  @override
  State<LogHistoryScreen> createState() => _LogHistoryScreenState();
}

class _LogHistoryScreenState extends State<LogHistoryScreen> {
  final DatabaseReference _logsRef = FirebaseDatabase.instance.ref('trashbin_logs');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Log Riwayat'),
        backgroundColor: const Color(0xFF121212),
      ),
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: StreamBuilder<DatabaseEvent>(
          stream: _logsRef.orderByChild('timestamp').onValue,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.white)));
            }
            if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
              return const Center(child: Text('Belum ada riwayat', style: TextStyle(color: Colors.white70)));
            }

            final raw = snapshot.data!.snapshot.value as Map;
            // Map entries menjadi list terurut descending (latest di atas)
            final entries = raw.entries.map((e) {
              final m = Map<String, dynamic>.from(e.value as Map);
              m['key'] = e.key;
              return m;
            }).toList();

            entries.sort((a, b) {
              final ta = DateTime.tryParse(a['timestamp'] ?? '') ?? DateTime(1970);
              final tb = DateTime.tryParse(b['timestamp'] ?? '') ?? DateTime(1970);
              return tb.compareTo(ta);
            });

            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final item = entries[i];
                final ts = item['timestamp'] ?? '';
                final event = item['event'] ?? '';
                final openCount = item['open_count']?.toString();
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFF111111), borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [
                    Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.event_note, color: Colors.white)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(event.toString(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        Text(ts.toString(), style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12)),
                      ]),
                    ),
                    if (openCount != null) Text('$openCount x', style: const TextStyle(color: Colors.white70)),
                  ]),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
