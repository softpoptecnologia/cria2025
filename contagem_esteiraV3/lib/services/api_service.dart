// lib/services/api_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Exceção amigável para erros da API/HTTP.
class ApiException implements Exception {
  final int? statusCode;
  final String message;
  final String? body;

  ApiException(this.message, {this.statusCode, this.body});

  @override
  String toString() =>
      'ApiException(${statusCode ?? '-'}) $message${body != null ? ' | $body' : ''}';
}

class ApiService {
  // ----------- Config / Storage -----------
  static const _kApiBaseUrlKey = 'apiBaseUrl';

  /// Padrão inicial (pode trocar). O usuário altera nas Configurações.
  static const String defaultBaseUrl = 'http://192.168.0.104:5000';

  static const Duration _timeout = Duration(seconds: 8);

  // Método público para a UI acessar a URL base
  static Future<String> getBaseUrl() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_kApiBaseUrlKey) ?? defaultBaseUrl;
    return _normalizeBaseUrl(raw);
  }

  static Future<void> setBaseUrl(String url) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kApiBaseUrlKey, _normalizeBaseUrl(url));
  }

  static String _normalizeBaseUrl(String url) {
    var u = url.trim();
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    return u;
  }

  static Map<String, String> get _jsonHeaders => const {
        'Content-Type': 'application/json; charset=utf-8',
        'Accept': 'application/json',
      };

  static Uri _join(String base, String path, [Map<String, String>? qp]) {
    final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final p = path.startsWith('/') ? path : '/$path';
    final u = Uri.parse('$b$p');
    return qp == null ? u : u.replace(queryParameters: qp);
  }

  // ----------- Helpers HTTP -----------
  static Future<http.Response> _getRaw(String path,
      {Map<String, String>? query}) async {
    final base = await getBaseUrl();
    final uri = _join(base, path, query);
    try {
      return await http.get(uri, headers: _jsonHeaders).timeout(_timeout);
    } on TimeoutException {
      throw ApiException('Tempo de resposta esgotado (GET $path)');
    } catch (e) {
      throw ApiException('Falha de rede (GET $path): $e');
    }
  }

  static Future<http.Response> _postRaw(String path, Map<String, dynamic> body,
      {int expected = 200}) async {
    final base = await getBaseUrl();
    final uri = _join(base, path);
    try {
      final r = await http
          .post(uri, headers: _jsonHeaders, body: jsonEncode(body))
          .timeout(_timeout);
      return r;
    } on TimeoutException {
      throw ApiException('Tempo de resposta esgotado (POST $path)');
    } catch (e) {
      throw ApiException('Falha de rede (POST $path): $e');
    }
  }

  static dynamic _decode(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return body;
    }
  }

  static Map<String, dynamic> _ensureMap(dynamic decoded, String onError) {
    if (decoded is Map<String, dynamic>) return decoded;
    throw ApiException(onError, body: decoded.toString());
  }

  static List<Map<String, dynamic>> _ensureListOfMap(
      dynamic decoded, String onError) {
    if (decoded is List) {
      return decoded.map<Map<String, dynamic>>((e) {
        if (e is Map<String, dynamic>) return e;
        return Map<String, dynamic>.from(e as Map);
      }).toList();
    }
    throw ApiException(onError, body: decoded.toString());
  }

  // ----------- Health -----------
  static Future<bool> checkHealth() async {
    final r = await _getRaw('/health');
    return r.statusCode == 200;
  }

  // ----------- Listas -----------
  static Future<List<Map<String, dynamic>>> getClientes() async {
    final r = await _getRaw('/clientes');
    if (r.statusCode != 200) {
      throw ApiException('Falha ao carregar clientes',
          statusCode: r.statusCode, body: r.body);
    }
    return _ensureListOfMap(_decode(r.body), 'Resposta inválida em /clientes');
  }

  static Future<List<Map<String, dynamic>>> getProdutos() async {
    final r = await _getRaw('/produtos');
    if (r.statusCode != 200) {
      throw ApiException('Falha ao carregar produtos',
          statusCode: r.statusCode, body: r.body);
    }
    return _ensureListOfMap(_decode(r.body), 'Resposta inválida em /produtos');
  }

  static Future<List<Map<String, dynamic>>> getDispositivos() async {
    final r = await _getRaw('/dispositivos');
    if (r.statusCode != 200) {
      throw ApiException('Falha ao carregar dispositivos',
          statusCode: r.statusCode, body: r.body);
    }
    return _ensureListOfMap(
        _decode(r.body), 'Resposta inválida em /dispositivos');
  }

  static Future<List<Map<String, dynamic>>> listarSessoes(
      {int page = 1, int size = 20}) async {
    final r = await _getRaw('/sessoes', query: {
      'page': '$page',
      'size': '$size',
    });
    if (r.statusCode != 200) {
      throw ApiException('Falha ao listar sessões',
          statusCode: r.statusCode, body: r.body);
    }
    final decoded = _decode(r.body);
    final map = _ensureMap(decoded, 'Resposta inválida em /sessoes');
    final rows = map['rows'];
    if (rows is List) {
      return rows
          .cast<Map>()
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    if (decoded is List) {
      return _ensureListOfMap(decoded, 'Resposta inválida em /sessoes');
    }
    throw ApiException('Campo "rows" ausente em /sessoes', body: r.body);
  }

  // ----------- Sessões -----------
  static Future<int> criarSessao({
    required int clienteId,
    required int produtoId,
    required String lote,
    required int operadorId,
    required String dispositivoCodigo,
  }) async {
    final r = await _postRaw(
        '/sessoes',
        {
          'cliente_id': clienteId,
          'produto_id': produtoId,
          'lote': lote,
          'operador_id': operadorId,
          'dispositivo_codigo': dispositivoCodigo,
        },
        expected: 201);

    if (r.statusCode != 201) {
      throw ApiException('Falha ao iniciar sessão',
          statusCode: r.statusCode, body: r.body);
    }

    final data =
        _ensureMap(_decode(r.body), 'Resposta inválida ao criar sessão');
    final id = data['sessao_id'];
    if (id is int) return id;
    throw ApiException('Campo "sessao_id" ausente na resposta', body: r.body);
  }

  static Future<Map<String, dynamic>> obterSessao(int sessaoId) async {
    final r = await _getRaw('/sessoes/$sessaoId');
    if (r.statusCode != 200) {
      throw ApiException('Falha ao obter sessão',
          statusCode: r.statusCode, body: r.body);
    }
    final data =
        _ensureMap(_decode(r.body), 'Resposta inválida em /sessoes/:id');
    return data;
  }

  static Future<void> finalizarSessao({
    required int sessaoId,
    required String dispositivoCodigo,
  }) async {
    final r = await _postRaw('/sessoes/$sessaoId/finalizar', {
      'dispositivo_codigo': dispositivoCodigo,
    });

    if (r.statusCode != 200) {
      throw ApiException('Falha ao finalizar sessão',
          statusCode: r.statusCode, body: r.body);
    }

    final decoded = _decode(r.body);
    if (decoded is Map && decoded.containsKey('ok')) {
      final ok = decoded['ok'] == true;
      if (!ok) {
        throw ApiException('API retornou ok=false ao finalizar', body: r.body);
      }
    }
  }
}
