// lib/pages/history_page.dart

import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'session_page.dart';
import '../widgets/custom_card.dart';
import '../widgets/section_header.dart';
import '../widgets/history_item.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  bool _loading = true;
  String? _erro;
  int _page = 1;
  final _rows = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool append = false}) async {
    setState(() {
      _loading = true;
      _erro = null;
    });
    try {
      final res = await ApiService.listarSessoes(page: _page, size: 20);
      if (append) {
        _rows.addAll(res);
      } else {
        _rows.clear();
        _rows.addAll(res);
      }
    } catch (e) {
      _erro = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Histórico de Sessões'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _page = 1;
          await _load();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_erro != null) Text(_erro!, style: TextStyle(color: cs.error)),
            CustomCard(
              child: Column(
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Buscar por cliente, produto ou lote...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.background,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Chip(
                          label: const Text('Todos os clientes'),
                          backgroundColor:
                              Theme.of(context).colorScheme.background,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Chip(
                          label: const Text('Todos os produtos'),
                          backgroundColor:
                              Theme.of(context).colorScheme.background,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_rows.isEmpty)
              const Center(child: Text('Nenhum registro encontrado.'))
            else
              ..._rows.map((r) {
                // Conversão explícita para int
                final int id = r['id'] is String
                    ? int.tryParse(r['id']) ?? 0
                    : r['id'] ?? 0;
                final int total = r['total'] is String
                    ? int.tryParse(r['total']) ?? 0
                    : r['total'] ?? 0;

                return HistoryItem(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SessionPage(
                        sessaoId: id,
                        dispositivoCodigo: r['dispositivo_codigo'] ?? '',
                      ),
                    ),
                  ),
                  status: (r['status'] ?? '').toString(),
                  id: id,
                  cliente: r['cliente'] ?? '',
                  produto: r['produto'] ?? '',
                  total: total,
                  inicio: (r['inicio'] ?? '').toString(),
                  fim: r['fim'] ?? '',
                );
              }),
            if (_rows.isNotEmpty && !_loading)
              Align(
                alignment: Alignment.center,
                child: FilledButton.tonalIcon(
                  onPressed: () async {
                    _page++;
                    await _load(append: true);
                  },
                  icon: const Icon(Icons.expand_more),
                  label: const Text('Carregar mais'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
