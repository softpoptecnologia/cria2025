// lib/pages/select_session_page.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import 'session_page.dart';
import '../widgets/custom_card.dart';
import '../widgets/section_header.dart';

class SelectSessionPage extends StatefulWidget {
  const SelectSessionPage({super.key});

  @override
  State<SelectSessionPage> createState() => _SelectSessionPageState();
}

class _SelectSessionPageState extends State<SelectSessionPage> {
  final _formKey = GlobalKey<FormState>();
  int? _clienteId;
  int? _produtoId;
  int? _operadorId = 1;
  String _lote = 'L1';
  String? _dispositivoCodigo;
  bool _loading = false;
  bool _loadingData = true;
  String? _erro;

  List<Map<String, dynamic>> _clientes = [];
  List<Map<String, dynamic>> _produtos = [];
  List<Map<String, dynamic>> _dispositivos = [];

  @override
  void initState() {
    super.initState();
    _carregarTudo();
  }

  Future<void> _carregarTudo() async {
    setState(() {
      _erro = null;
      _loadingData = true;
    });
    try {
      await _carregarPrefs();
      final results = await Future.wait([
        ApiService.getClientes(),
        ApiService.getProdutos(),
        ApiService.getDispositivos(),
      ]);
      _clientes = results[0];
      _produtos = results[1];
      _dispositivos = results[2];
      _clienteId ??= _clientes.isNotEmpty ? _clientes.first['id'] as int : null;
      _produtoId ??= _produtos.isNotEmpty ? _produtos.first['id'] as int : null;
      _dispositivoCodigo ??= _dispositivos.isNotEmpty
          ? _dispositivos.first['codigo'] as String
          : null;
    } catch (e) {
      _erro = e.toString();
    } finally {
      if (mounted) setState(() => _loadingData = false);
    }
  }

  Future<void> _recarregarDispositivos() async {
    setState(() => _erro = null);
    try {
      final list = await ApiService.getDispositivos();
      setState(() {
        _dispositivos = list;
        if (_dispositivos.isNotEmpty &&
            (_dispositivoCodigo == null ||
                !_dispositivos.any((d) => d['codigo'] == _dispositivoCodigo))) {
          _dispositivoCodigo = _dispositivos.first['codigo'] as String;
        }
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dispositivos recarregados')),
      );
    } catch (e) {
      setState(() => _erro = e.toString());
    }
  }

  Future<void> _carregarPrefs() async {
    final sp = await SharedPreferences.getInstance();
    _clienteId = sp.getInt('clienteId');
    _produtoId = sp.getInt('produtoId');
    _operadorId = sp.getInt('operadorId') ?? 1;
    _lote = sp.getString('lote') ?? 'L1';
    _dispositivoCodigo =
        sp.getString('dispositivoCodigo') ?? _dispositivoCodigo;
  }

  Future<void> _salvarPrefs() async {
    final sp = await SharedPreferences.getInstance();
    if (_clienteId != null) await sp.setInt('clienteId', _clienteId!);
    if (_produtoId != null) await sp.setInt('produtoId', _produtoId!);
    if (_operadorId != null) await sp.setInt('operadorId', _operadorId!);
    await sp.setString('lote', _lote);
    if (_dispositivoCodigo != null) {
      await sp.setString('dispositivoCodigo', _dispositivoCodigo!);
    }
  }

  Future<void> _iniciar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_clienteId == null ||
        _produtoId == null ||
        _dispositivoCodigo == null) {
      setState(() => _erro = 'Selecione cliente, produto e dispositivo.');
      return;
    }
    setState(() {
      _erro = null;
      _loading = true;
    });

    try {
      final sessaoId = await ApiService.criarSessao(
        clienteId: _clienteId!,
        produtoId: _produtoId!,
        lote: _lote.trim().isEmpty ? 'L1' : _lote.trim(),
        operadorId: _operadorId ?? 1,
        dispositivoCodigo: _dispositivoCodigo!,
      );

      await _salvarPrefs();
      final sp = await SharedPreferences.getInstance();
      await sp.setInt('lastSessaoId', sessaoId);
      await sp.setString('lastSessaoDisp', _dispositivoCodigo!);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SessionPage(
            sessaoId: sessaoId,
            dispositivoCodigo: _dispositivoCodigo!,
          ),
        ),
      );
    } catch (e) {
      setState(() => _erro = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final col = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Iniciar Nova Contagem'),
      ),
      body: RefreshIndicator(
        onRefresh: _carregarTudo,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_erro != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_erro!, style: TextStyle(color: col.error)),
                ),
              if (_loadingData)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (!_loadingData)
                CustomCard(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SectionHeader(
                          title: 'Dados da produção',
                          icon: Icons.tune,
                          color: col.primary,
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<int>(
                          value: _clienteId,
                          items: _clientes
                              .map((c) => DropdownMenuItem<int>(
                                  value: c['id'] as int,
                                  child: Text(c['nome'] as String)))
                              .toList(),
                          onChanged: (v) => setState(() => _clienteId = v),
                          decoration: const InputDecoration(
                            labelText: 'Cliente',
                            prefixIcon: Icon(Icons.business_outlined),
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) =>
                              v == null ? 'Selecione um cliente' : null,
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<int>(
                          value: _produtoId,
                          items: _produtos
                              .map((p) => DropdownMenuItem<int>(
                                  value: p['id'] as int,
                                  child: Text(p['nome'] as String)))
                              .toList(),
                          onChanged: (v) => setState(() => _produtoId = v),
                          decoration: const InputDecoration(
                            labelText: 'Produto',
                            prefixIcon: Icon(Icons.local_drink_outlined),
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) =>
                              v == null ? 'Selecione um produto' : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          initialValue: '${_operadorId ?? 1}',
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Operador ID',
                            prefixIcon: Icon(Icons.badge_outlined),
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) {
                            final n = int.tryParse((v ?? '').trim());
                            if (n == null || n <= 0) {
                              return 'Informe um inteiro > 0';
                            }
                            return null;
                          },
                          onChanged: (v) =>
                              _operadorId = int.tryParse(v.trim()) ?? 1,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          initialValue: _lote,
                          decoration: const InputDecoration(
                            labelText: 'Lote',
                            prefixIcon:
                                Icon(Icons.confirmation_number_outlined),
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (v) => _lote = v,
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          value: _dispositivoCodigo,
                          items: _dispositivos
                              .map((d) => DropdownMenuItem<String>(
                                  value: d['codigo'] as String,
                                  child: Text(
                                      '${d['codigo']}${(d['descricao'] as String).isNotEmpty ? ' - ${d['descricao']}' : ''}')))
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _dispositivoCodigo = v),
                          decoration: const InputDecoration(
                            labelText: 'Dispositivo',
                            prefixIcon: Icon(Icons.memory_outlined),
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) => (v == null || v.isEmpty)
                              ? 'Selecione um dispositivo'
                              : null,
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: _loading ? null : _iniciar,
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: Text(
                              _loading ? 'Iniciando...' : 'Iniciar sessão'),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
