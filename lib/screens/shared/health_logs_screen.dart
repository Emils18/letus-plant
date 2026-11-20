import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/lettuce_scan_report.dart';
import '../../widgets/lettuce_scan_report_card.dart';
import 'scan_session_report_screen.dart';

class HealthLogsScreen extends StatefulWidget {
  const HealthLogsScreen({
    super.key,
    this.farmerId,
    this.productName,
    this.readOnlyBuyer = false,
    this.title,
  });

  final String? farmerId;
  final String? productName;
  final bool readOnlyBuyer;
  final String? title;

  @override
  State<HealthLogsScreen> createState() => _HealthLogsScreenState();
}

class _HealthLogsScreenState extends State<HealthLogsScreen> {
  static const _background = Color(0xfff6fbf7);
  static const _green = Color(0xff2f6b3b);
  static const _ink = Color(0xff1e2a1f);
  static const _muted = Color(0xff4d6050);

  final _supabase = Supabase.instance.client;
  bool _loading = false;
  bool _loadFailed = false;
  List<Map<String, dynamic>> _logs = [];
  Map<String, List<Map<String, dynamic>>> _groups = {};
  final _sessionMetadata = <String, Map<String, dynamic>>{};

  @override
  void initState() {
    super.initState();
    _loadHealthLogs();
  }

  Future<void> _loadHealthLogs() async {
    if (_loading) return;
    setState(() => _loading = true);

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw StateError('Sign in to view scan history.');
      final owner = widget.readOnlyBuyer ? widget.farmerId ?? user.id : user.id;
      final logs = <Map<String, dynamic>>[];
      const pageSize = 250;
      for (var from = 0; ; from += pageSize) {
        final page = await _supabase
            .from('diagnostic_logs')
            .select()
            .eq('user_id', owner)
            .order('created_at', ascending: false)
            .order('id', ascending: false)
            .range(from, from + pageSize - 1);
        if (!mounted) return;
        logs.addAll(page);
        if (page.length < pageSize) break;
      }

      final groups = <String, List<Map<String, dynamic>>>{};
      if (!widget.readOnlyBuyer) {
        for (final log in logs) {
          final id = LettuceScanReport.text(log, ['scan_session_id']);
          if (id.isNotEmpty) (groups[id] ??= []).add(log);
        }
      }

      if (!mounted) return;
      setState(() {
        _logs = logs;
        _groups = groups;
        _sessionMetadata.clear();
        _loadFailed = false;
      });
    } catch (error) {
      debugPrint('Health log load failed: $error');
      if (mounted) setState(() => _loadFailed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openSession(String id, List<Map<String, dynamic>> logs) async {
    // Read session timestamps separately so a missing session table cannot
    // hide the individual scans or legacy history.
    var session = _sessionMetadata[id];
    if (session == null) {
      try {
        session = await _supabase
            .from('scan_sessions')
            .select('started_at, completed_at')
            .eq('id', id)
            .eq('user_id', _supabase.auth.currentUser!.id)
            .maybeSingle();
        if (session != null) _sessionMetadata[id] = session;
      } catch (error) {
        debugPrint('Scan session metadata unavailable: $error');
      }
    }

    if (!mounted) return;
    final chronological = logs.reversed.toList();
    final startedAt =
        DateTime.tryParse(
          LettuceScanReport.text(session ?? {}, ['started_at']),
        ) ??
        LettuceScanReport.capturedAt(chronological.first);
    final completedAt = DateTime.tryParse(
      LettuceScanReport.text(session ?? {}, ['completed_at']),
    );
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ScanSessionReportScreen(
          scans: chronological,
          startedAt: startedAt,
          completedAt: completedAt,
          historyMode: true,
        ),
      ),
    );
  }




  void _openOverallReport() {
    if (_logs.isEmpty) return;

    final scans = _logs.reversed.toList();

    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ScanSessionReportScreen(
          scans: scans,
          startedAt: LettuceScanReport.capturedAt(scans.first),
          completedAt: null,
          historyMode: true,
          reportTitle: 'Overall Health Report',
        ),
      ),
    );
  }




  @override
  Widget build(BuildContext context) {
    final healthy = _logs.where(_isHealthy).length;
    final risk = _logs.where((scan) {
      final key = LettuceScanReport.diseaseKey(
        LettuceScanReport.diseaseName(scan),
      );
      return key != 'healthy' &&
          LettuceScanReport.diseaseNames.containsKey(key);
    }).length;
    final sessions = _groups.entries.toList();

    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: _ink,
        title: Text(
          widget.title ??
              (widget.readOnlyBuyer
                  ? 'Product Health Logs'
                  : 'Scan History Logs'),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh scan history',
            onPressed: _loading ? null : _loadHealthLogs,
            icon: const Icon(Icons.refresh_rounded, color: _green),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: _green,
        onRefresh: _loadHealthLogs,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              sliver: SliverList.list(
                children: [
                  if (widget.productName case final name?)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Crop: $name',
                        style: const TextStyle(
                          color: _green,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _metric('Total', _logs.length, Icons.history),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _metric(
                          'Healthy',
                          healthy,
                          Icons.verified_outlined,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _metric(
                          'Risk',
                          risk,
                          Icons.warning_amber_rounded,
                        ),
                      ),
                    ],
                  ),
                  if (_logs.length > healthy + risk)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '${_logs.length - healthy - risk} scans need review',
                        style: const TextStyle(color: _muted, fontSize: 15),
                      ),
                    ),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: LinearProgressIndicator(color: _green),
                    ),
                  if (_loadFailed)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Scan history could not be refreshed. Check your connection and try again.',
                        style: TextStyle(color: _ink, fontSize: 16),
                      ),
                    ),
                  if (!_loading && !_loadFailed && _logs.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 22),
                      child: Text(
                        'No scans saved yet. Take a lettuce photo to start.',
                        style: TextStyle(color: _ink, fontSize: 16),
                      ),
                    ),
                  if (sessions.isNotEmpty)

                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF173E29),
                          Color(0xFF34814B),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(23),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(18),
                      leading: const Icon(
                        Icons.assessment_rounded,
                        color: Color(0xFFD8F973),
                        size: 35,
                      ),
                      title: const Text(
                        'Overall Health Report',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      subtitle: const Text(
                        'All scans, disease breakdown, treatments and selling guidance',
                        style: TextStyle(
                          color: Color(0xFFE1F1E2),
                        ),
                      ),
                      trailing: const Icon(
                        Icons.arrow_forward_ios,
                        color: Colors.white,
                        size: 17,
                      ),
                      onTap: _logs.isEmpty ? null : _openOverallReport,
                    ),
                  ),



                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF173E29),
                          Color(0xFF34814B),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(23),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(18),
                      leading: const Icon(
                        Icons.assessment_rounded,
                        color: Color(0xFFD8F973),
                        size: 35,
                      ),
                      title: const Text(
                        'Overall Health Report',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      subtitle: const Text(
                        'All scans, disease breakdown, treatments and selling guidance',
                        style: TextStyle(
                          color: Color(0xFFE1F1E2),
                        ),
                      ),
                      trailing: const Icon(
                        Icons.arrow_forward_ios,
                        color: Colors.white,
                        size: 17,
                      ),
                      onTap: _logs.isEmpty ? null : _openOverallReport,
                    ),
                  ),


                    _sectionTitle('Previous scan sessions'),
                ],
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList.builder(
                itemCount: sessions.length,
                itemBuilder: (_, index) => _sessionCard(sessions[index]),
              ),
            ),
            if (_logs.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
                sliver: SliverToBoxAdapter(
                  child: _sectionTitle('Individual scans'),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
              sliver: SliverList.builder(
                itemCount: _logs.length,
                itemBuilder: (_, index) => LettuceScanReportCard(
                  key: ValueKey(_logs[index]['id']),
                  scan: _logs[index],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isHealthy(Map<String, dynamic> scan) =>
      LettuceScanReport.diseaseKey(LettuceScanReport.diseaseName(scan)) ==
      'healthy';

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: Text(
      title,
      style: const TextStyle(
        color: _ink,
        fontSize: 21,
        fontWeight: FontWeight.w800,
      ),
    ),
  );

  Widget _metric(String label, int count, IconData icon) => Card(
    color: Colors.white,
    elevation: 0,
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 5),
      child: Column(
        children: [
          Icon(icon, color: _green, size: 25),
          Text(
            '$count',
            style: const TextStyle(
              color: _ink,
              fontSize: 23,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 15),
          ),
        ],
      ),
    ),
  );

  Widget _sessionCard(MapEntry<String, List<Map<String, dynamic>>> entry) {
    final date = LettuceScanReport.capturedAt(entry.value.first);
    final count = entry.value.length;
    return Card(
      color: Colors.white,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        minTileHeight: 66,
        contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 14),
        leading: const Icon(Icons.assessment_outlined, color: _green),
        title: Text(
          '$count saved ${count == 1 ? 'photo' : 'photos'}',
          style: const TextStyle(
            color: _ink,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Text(
          date == null
              ? 'Open session report'
              : DateFormat.yMMMd().add_jm().format(date.toLocal()),
          style: const TextStyle(color: _muted, fontSize: 15),
        ),
        trailing: const Icon(Icons.chevron_right, color: _green),
        onTap: () => _openSession(entry.key, entry.value),
      ),
    );
  }
}
