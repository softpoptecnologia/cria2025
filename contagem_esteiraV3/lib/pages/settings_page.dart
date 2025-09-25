// lib/pages/settings_page.dart

import 'package:flutter/material.dart';
import '../widgets/custom_card.dart';
import '../widgets/section_header.dart';
import '../services/api_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _apiController = TextEditingController();
  bool _loading = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _loadApiUrl();
  }

  Future<void> _loadApiUrl() async {
    final url = await ApiService.getBaseUrl();
    _apiController.text = url;
  }

  Future<void> _saveApiUrl() async {
    setState(() {
      _loading = true;
      _erro = null;
    });
    try {
      await ApiService.setBaseUrl(_apiController.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('URL da API salva com sucesso!')),
        );
      }
    } catch (e) {
      setState(() => _erro = e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar URL: $_erro')),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurações'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            CustomCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionHeader(
                    title: 'Configuração da API',
                    icon: Icons.cloud_outlined,
                    color: cs.primary,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _apiController,
                    decoration: const InputDecoration(
                      labelText: 'URL da API',
                      hintText: 'Ex: http://192.168.1.10:5000',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _loading ? null : _saveApiUrl,
                    icon: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.save),
                    label: Text(_loading ? 'Salvando...' : 'Salvar URL da API'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            CustomCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionHeader(
                    title: 'Dispositivos ESP32',
                    icon: Icons.electrical_services_outlined,
                    color: cs.primary,
                  ),
                  const SizedBox(height: 16),
                  _buildDeviceItem('ESP32_01', 'Conectado', true),
                  _buildDeviceItem('ESP32_02', 'Desconectado', false),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceItem(String name, String status, bool isConnected) {
    return ListTile(
      leading: Icon(
        isConnected ? Icons.check_circle_outline : Icons.cancel_outlined,
        color: isConnected ? Colors.green : Colors.red,
      ),
      title: Text(name),
      subtitle: Text(status),
      trailing: IconButton(
        icon: const Icon(Icons.edit),
        onPressed: () {},
      ),
    );
  }
}
