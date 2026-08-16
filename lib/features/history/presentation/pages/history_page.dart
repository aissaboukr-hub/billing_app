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

  Future<void> _exportExcel() async {
    try {
      await DataTransferService.exportHistoryToExcel(history: _history);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Historique exporté en Excel.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
    }
  }

  Future<void> _syncGoogleSheets() async {
    final endpoint = HiveDatabase.settingsBox.get('google_sheets_export_url', defaultValue: '') as String;
    try {
      await DataTransferService.exportHistoryToGoogleSheets(history: _history, endpoint: endpoint);
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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: _history.isEmpty ? null : _exportExcel, icon: const Icon(Icons.table_view), label: const Text('Excel'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(onPressed: _history.isEmpty ? null : _syncGoogleSheets, icon: const Icon(Icons.cloud_upload), label: const Text('Google Sheets'))),
          ]),
        ),
        Expanded(
          child: _history.isEmpty
              ? const Center(child: Text('Aucune opération enregistrée.'))
              : RefreshIndicator(
                  onRefresh: () async => setState(() => _history = HistoryService.getAll()),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _history.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final operation = _history[index];
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
    );
  }
}
