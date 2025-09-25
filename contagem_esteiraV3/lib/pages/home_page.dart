// lib/pages/home_page.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import 'session_page.dart';
import '../widgets/action_card.dart';
import '../widgets/custom_card.dart';
import '../widgets/metric_tile.dart';
import '../widgets/section_header.dart';

// -------- helpers seguros --------
num _asNum(dynamic v) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v) ?? 0;
  return 0;
}

DateTime? _parseWhen(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  return DateTime.tryParse(s);
}

String _fmtHMS(Duration d) {
  final h = d.inHours.remainder(100).toString().padLeft(2, '0');
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$h:$m:$s';
}

// -------- Sparkline (mini-gráfico) - Mantido igual --------
class Sparkline extends StatelessWidget {
  final List<num> data;
  final double height;
  final Color color;
  const Sparkline({
    super.key,
    required this.data,
    this.height = 56,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final doubles = data.map((e) => e.toDouble()).toList();
    return SizedBox(
      height: height,
      child: CustomPaint(painter: _SparklinePainter(doubles, color)),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> d;
  final Color color;
  _SparklinePainter(this.d, this.color);

  @override
  void paint(Canvas c, Size s) {
    if (d.isEmpty) return;
    final minV = d.reduce(min);
    final maxV = d.reduce(max);
    final range = (maxV - minV).abs() < 1e-6 ? 1.0 : (maxV - minV);

    final path = Path();
    final p = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    for (var i = 0; i < d.length; i++) {
      final x = (d.length == 1) ? 0.0 : i / (d.length - 1) * s.width;
      final y = s.height - ((d[i] - minV) / range) * s.height;
      if (i == 0)
        path.moveTo(x, y);
      else
        path.lineTo(x, y);
    }
    c.drawPath(path, p);

    final lastX = s.width;
    final lastY = s.height - ((d.last - minV) / range) * s.height;
    c.drawCircle(Offset(lastX, lastY), 3.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) {
    if (old.color != color) return true;
    if (old.d.length != d.length) return true;
    for (var i = 0; i < d.length; i++) {
      if (old.d[i] != d[i]) return true;
    }
    return false;
  }

  @override
  bool shouldRebuildSemantics(covariant _SparklinePainter oldDelegate) => false;
}

// ---------- Home - Lógica e UI refatoradas ----------
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _navIndex = 0;
  int? _lastSessaoId;
  String? _lastDisp;
  Map<String, dynamic>? _sessao;
  bool _loading = true;
  String? _erro;
  bool _apiOnline = false;
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  double _mediaMin = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _erro = null;
    });
    try {
      _apiOnline = await ApiService.checkHealth();
      final sp = await SharedPreferences.getInstance();
      _lastSessaoId = sp.getInt('lastSessaoId');
      _lastDisp = sp.getString('lastSessaoDisp');

      if (_lastSessaoId != null) {
        final s = await ApiService.obterSessao(_lastSessaoId!);
        if ((s['status'] ?? '').toString().toLowerCase() == 'finalizada') {
          await sp.remove('lastSessaoId');
          await sp.remove('lastSessaoDisp');
          _lastSessaoId = null;
          _lastDisp = null;
          _sessao = null;
        } else {
          _sessao = s;
        }
      } else {
        _sessao = null;
      }
      _recomputeMetrics();
    } catch (e) {
      _erro = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _tick() {
    if (_sessao == null) return;
    final inicio = _parseWhen(_sessao!['inicio']);
    if (inicio == null) return;
    final now = DateTime.now();
    _elapsed = now.difference(inicio);
    _recomputeMetrics();
    if (mounted) setState(() {});
  }

  void _recomputeMetrics() {
    final total = _asNum(_sessao?['total']).toDouble();
    final mins = max(1, _elapsed.inSeconds / 60.0);
    _mediaMin = total / mins;
  }

  List<num> _serieUltimas() {
    final l = (_sessao?['ultimas_leituras'] as List<dynamic>?) ?? [];
    int sum = 0;
    final series = <int>[];
    for (final e in l) {
      final m = (e as Map).cast<String, dynamic>();
      sum += _asNum(m['contagem_incremental']).toInt();
      series.add(sum);
    }
    return series.isEmpty ? [0] : series;
  }

  Future<void> _finalizarSessao() async {
    if (_lastSessaoId == null) return;
    try {
      await ApiService.finalizarSessao(
        sessaoId: _lastSessaoId!,
        dispositivoCodigo: _lastDisp ?? '',
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sessão finalizada')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao finalizar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final totalAtual = _asNum(_sessao?['total']).toInt();
    final statusAtual = (_sessao?['status'] ?? '...').toString();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Painel de Produção'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: cs.onBackground,
        actions: [
          _ApiBadge(online: _apiOnline),
          IconButton(
            tooltip: 'Configurações',
            onPressed: () =>
                Navigator.pushNamed(context, '/settings').then((_) => _load()),
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_erro != null) Text(_erro!, style: TextStyle(color: cs.error)),
            CustomCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionHeader(
                    title: 'Sessão Atual',
                    icon: Icons.info_outline,
                    color: cs.primary,
                  ),
                  const SizedBox(height: 12),
                  _buildDataRow(Icons.factory_outlined, 'Indústria XYZ'),
                  _buildDataRow(Icons.build_outlined, 'Garra Tipo A'),
                  _buildDataRow(Icons.person_outline, 'José Silva'),
                  _buildDataRow(Icons.label_outlined, 'Lote: L-2025-0822'),
                  _buildDataRow(Icons.electrical_services_outlined, 'ESP32_01'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            CustomCard(
              child: Column(
                children: [
                  const Text('CONTAGEM ATUAL',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Text(
                    totalAtual.toString(),
                    style: TextStyle(
                      fontSize: 60,
                      fontWeight: FontWeight.bold,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _lastSessaoId != null
                            ? null
                            : () => Navigator.pushNamed(context, '/start')
                                .then((_) => _load()),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Iniciar'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30)),
                        ),
                      ),
                      const SizedBox(width: 20),
                      ElevatedButton.icon(
                        onPressed:
                            _lastSessaoId != null ? _finalizarSessao : null,
                        icon: const Icon(Icons.stop),
                        label: const Text('Parar'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: MetricTile(
                    label: 'Tempo de Cont.',
                    value: _fmtHMS(_elapsed),
                    icon: Icons.timer,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: MetricTile(
                    label: 'Média por Min.',
                    value: _mediaMin.toStringAsFixed(1),
                    icon: Icons.speed,
                    color: cs.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            CustomCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionHeader(
                    title: 'Evolução da Contagem',
                    icon: Icons.show_chart,
                    color: cs.primary,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 200,
                    child: Sparkline(
                      data: _serieUltimas(),
                      color: cs.primary,
                      height: 200,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _navIndex,
        onDestinationSelected: (i) {
          setState(() => _navIndex = i);
          switch (i) {
            case 0:
              break;
            case 1:
              Navigator.pushNamed(context, '/start');
              break;
            case 2:
              Navigator.pushNamed(context, '/history');
              break;
            case 3:
              Navigator.pushNamed(context, '/settings');
              break;
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.speed), label: 'Dashboard'),
          NavigationDestination(
              icon: Icon(Icons.play_arrow_rounded), label: 'Iniciar'),
          NavigationDestination(icon: Icon(Icons.history), label: 'Histórico'),
          NavigationDestination(
              icon: Icon(Icons.settings), label: 'Configurações'),
        ],
      ),
    );
  }

  Widget _buildDataRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontSize: 16)),
        ],
      ),
    );
  }
}

class _ApiBadge extends StatelessWidget {
  final bool online;
  const _ApiBadge({required this.online});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = online ? Colors.green[100] : Colors.red[100];
    final fg = online ? Colors.green[800] : Colors.red[800];
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          Icon(online ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
              size: 18, color: fg),
          const SizedBox(width: 6),
          Text(online ? 'Online' : 'Offline',
              style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
