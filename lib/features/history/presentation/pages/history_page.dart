import 'package:flutter/material.dart';
import 'package:billing_app/core/utils/app_formatters.dart';
import 'package:billing_app/features/data_transfer/data/data_transfer_service.dart';
import 'package:billing_app/features/history/data/history_service.dart';
import 'package:billing_app/core/data/hive_database.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  late List<Map<String, dynamic>> _history;
  DateTimeRange? _dateRange;

  @override
  void initState() {
    super.initState();
    _history = HistoryService.getAll();
  }

  String _date(String value) {
    final date = DateTime.tryParse(value)?.toLocal();
    if (date == null) return value;
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  List<Map<String, dynamic>> get _filteredHistory {
    final range = _dateRange;
    if (range == null) return _history;
    return _history.where((operation) {
      final date = DateTime.tryParse('${operation['date'] ?? ''}')?.toLocal();
      if (date == null) return false;
      final day = DateTime(date.year, date.month, date.day);
      final start = DateTime(range.start.year, range.start.month, range.start.day);
      final end = DateTime(range.end.year, range.end.month, range.end.day);
      return !day.isBefore(start) && !day.isAfter(end);
    }).toList();
  }

  double get _filteredTotal => _filteredHistory.fold<double>(
        0,
        (sum, operation) => sum + ((operation['total'] as num?)?.toDouble() ?? 0),
      );

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _dateRange,
      locale: const Locale('fr', 'DZ'),
    );
    if (picked != null && mounted) setState(() => _dateRange = picked);
  }

  void _clearDateFilter() => setState(() => _dateRange = null);

  Future<void> _exportExcel() async {
    try {
      await DataTransferService.exportHistoryToExcel(history: _filteredHistory);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Historique exporté en Excel.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
    }
  }

  Future<void> _syncGoogleSheets() async {
    final endpoint = HiveDatabase.settingsBox.get('google_sheets_export_url', defaultValue: '') as String;
    try {
      await DataTransferService.exportHistoryToGoogleSheets(history: _filteredHistory, endpoint: endpoint);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Historique synchronisé avec Google Sheets.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Historique des opérations')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: _pickDateRange, icon: const Icon(Icons.date_range), label: Text(_dateRange == null ? 'Filtrer par date' : '${_dateRange!.start.day.toString().padLeft(2, '0')}/${_dateRange!.start.month.toString().padLeft(2, '0')} → ${_dateRange!.end.day.toString().padLeft(2, '0')}/${_dateRange!.end.month.toString().padLeft(2, '0')}'))),
            if (_dateRange != null) ...[
              const SizedBox(width: 8),
              IconButton(onPressed: _clearDateFilter, tooltip: 'Effacer le filtre', icon: const Icon(Icons.clear)),
            ],
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: _filteredHistory.isEmpty ? null : _exportExcel, icon: const Icon(Icons.table_view), label: const Text('Excel'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(onPressed: _filteredHistory.isEmpty ? null : _syncGoogleSheets, icon: const Icon(Icons.cloud_upload), label: const Text('Google Sheets'))),
          ]),
        ),
        Expanded(
          child: _history.isEmpty
              ? const Center(child: Text('Aucune opération enregistrée.'))
              : RefreshIndicator(
                  onRefresh: () async => setState(() => _history = HistoryService.getAll()),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _filteredHistory.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final operation = _filteredHistory[index];
                      final items = (operation['items'] as List?) ?? const [];
                      final count = items.fold<int>(0, (sum, item) => sum + ((item as Map)['quantite'] as num? ?? 0).toInt());
                      final total = (operation['total'] as num?)?.toDouble() ?? 0;
                      return Card(
                        child: ExpansionTile(
                          leading: const CircleAvatar(child: Icon(Icons.receipt_long)),
                          title: Text('${operation['type'] ?? 'Opération'} — ${AppFormatters.price(total)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('${_date('${operation['date'] ?? ''}')} • $count article(s)'),
                          children: [
                            for (final rawItem in items)
                              ListTile(
                                dense: true,
                                title: Text('${(rawItem as Map)['quantite'] ?? 0} × ${rawItem['produit'] ?? ''}'),
                                subtitle: Text('Code-barres : ${rawItem['codeBarres'] ?? ''}'),
                                trailing: Text(AppFormatters.price(((rawItem['total'] as num?)?.toDouble() ?? 0))),
                              ),
                            const Divider(height: 1),
                            Padding(padding: const EdgeInsets.all(12), child: Align(alignment: Alignment.centerRight, child: Text('Total : ${AppFormatters.price(total)}', style: const TextStyle(fontWeight: FontWeight.bold)))),
                          ],
                        ),
                      );
                    },
                  ),
                ),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, -2))],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_dateRange == null ? 'Total des opérations' : 'Total de la période', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(AppFormatters.price(_filteredTotal), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _filteredTotal < 0 ? Colors.red : Theme.of(context).primaryColor)),
            ],
          ),
        ),
      ),
    );
  }
}
