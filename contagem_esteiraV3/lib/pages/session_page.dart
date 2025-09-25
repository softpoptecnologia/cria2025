import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';

num _asNum(dynamic v) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v) ?? 0;
  return 0;
}

class SessionPage extends StatefulWidget {
  final int sessaoId;
  final String dispositivoCodigo;
  const SessionPage({
    super.key,
    required this.sessaoId,
    required this.dispositivoCodigo,
  });

  @override
  State<SessionPage> createState() => _SessionPageState();
}

class _SessionPageState extends State<SessionPage> {
  Timer? _timer;
  Map<String, dynamic>? _sessao;
  String? _erro;
  bool _finalizando = false;

  double _lastTotal = 0; // << agora double seguro p/ animação

  @override
  void initState() {
    super.initState();
    _carregar();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _carregar());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _carregar() async {
    try {
      final data = await ApiService.obterSessao(widget.sessaoId);
      setState(() {
        // guarda o total anterior como double (seguro mesmo se vier string)
        _lastTotal = _asNum(_sessao?['total']).toDouble();
        _sessao = data;
        _erro = null;
      });
    } catch (e) {
      setState(() => _erro = e.toString());
    }
  }

  Future<void> _finalizar() async {
    setState(() => _finalizando = true);
    try {
      await ApiService.finalizarSessao(
        sessaoId: widget.sessaoId,
        dispositivoCodigo: widget.dispositivoCodigo,
      );
      await _carregar();

      // opcional: limpar sessão atual do dashboard, se você usa isso
      // final sp = await SharedPreferences.getInstance();
      // await sp.remove('lastSessaoId');
      // await sp.remove('lastSessaoDisp');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sessão finalizada')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao finalizar: $e')),
      );
    } finally {
      setState(() => _finalizando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final totalNow = _asNum(_sessao?['total']).toDouble();
    final totalLabel = totalNow.toStringAsFixed(0);
    final status = (_sessao?['status'] ?? '...').toString();
    final leituras = (_sessao?['ultimas_leituras'] as List<dynamic>?) ?? [];

    return Scaffold(
      appBar: AppBar(
        title: Text('Sessão #${widget.sessaoId}'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(child: _StatusChip(status: status)),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _carregar,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Card "hero" com gradiente e contador animado
            Card(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [cs.primaryContainer, cs.primary.withOpacity(.9)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
                child: Row(
                  children: [
                    Container(
                      height: 64,
                      width: 64,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(.18),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(Icons.countertops,
                          size: 34, color: cs.onPrimary),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Total contado',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                      color: cs.onPrimary,
                                      fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          TweenAnimationBuilder<double>(
                            duration: const Duration(milliseconds: 450),
                            tween: Tween<double>(
                              begin: _lastTotal,
                              end: totalNow,
                            ),
                            builder: (_, value, __) => Text(
                              value.toStringAsFixed(0),
                              style: TextStyle(
                                color: cs.onPrimary,
                                fontSize: 42,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text('Dispositivo: ${widget.dispositivoCodigo}',
                              style: TextStyle(
                                  color: cs.onPrimary.withOpacity(.9))),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _carregar,
                      icon: Icon(Icons.refresh, color: cs.onPrimary),
                      tooltip: 'Atualizar',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),

            if (_erro != null) Text(_erro!, style: TextStyle(color: cs.error)),

            const SizedBox(height: 8),

            // Últimas leituras
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.timeline, color: cs.primary),
                        const SizedBox(width: 8),
                        Text('Últimas leituras',
                            style: Theme.of(context).textTheme.titleMedium),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (leituras.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('Sem leituras recentes.'),
                      ),
                    ...List.generate(leituras.length, (i) {
                      final l = (leituras[i] as Map).cast<String, dynamic>();
                      final inc = _asNum(l['contagem_incremental']).toInt();
                      final ts = (l['timestamp'] ?? '').toString();
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: cs.secondaryContainer,
                          child: Text(
                            '$inc',
                            style: TextStyle(
                              color: cs.onSecondaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        title: const Text('Incremento'),
                        subtitle: Text(ts),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 4),
                      );
                    }),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            FilledButton.tonalIcon(
              onPressed: _finalizando ? null : _finalizar,
              style: FilledButton.styleFrom(
                backgroundColor: cs.errorContainer,
                foregroundColor: cs.onErrorContainer,
              ),
              icon: const Icon(Icons.stop_circle_outlined),
              label: Text(_finalizando ? 'Finalizando...' : 'Finalizar Sessão'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Color bg;
    Color fg;
    switch (status.toLowerCase()) {
      case 'ativa':
        bg = cs.secondaryContainer;
        fg = cs.onSecondaryContainer;
        break;
      case 'finalizada':
        bg = cs.tertiaryContainer;
        fg = cs.onTertiaryContainer;
        break;
      default:
        bg = cs.surfaceVariant;
        fg = cs.onSurfaceVariant;
    }
    return Container(
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(24)),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Text(status,
          style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
    );
  }
}
