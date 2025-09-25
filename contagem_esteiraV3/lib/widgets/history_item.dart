// lib/widgets/history_item.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class HistoryItem extends StatelessWidget {
  final int id;
  final String status;
  final String cliente;
  final String produto;
  final int total;
  final String inicio;
  final String fim;
  final VoidCallback? onTap;

  const HistoryItem({
    super.key,
    required this.id,
    required this.status,
    required this.cliente,
    required this.produto,
    required this.total,
    required this.inicio,
    required this.fim,
    this.onTap,
  });

  DateTime? _parse(String s) => s.isEmpty ? null : DateTime.tryParse(s);
  String _fmt(DateTime? dt) => dt == null
      ? ''
      : DateFormat('dd/MM/yyyy - HH:mm', 'pt_BR').format(dt.toLocal());

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // cores do chip de status
    Color bg, fg;
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

    final dtInicio = _parse(inicio);
    final dtFim = _parse(fim);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: ListTile(
        onTap: onTap,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),

        title: Text(
          'Sessão #$id • $cliente • $produto',
          style: const TextStyle(fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
        ),

        // duas linhas “oficiais” (evita quebra/overflow)
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Início: ${_fmt(dtInicio)}'),
            if (dtFim != null) Text('Fim: ${_fmt(dtFim)}'),
          ],
        ),

        // >>> Chip em cima, contagem embaixo (sem overflow)
        trailing: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 84),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text(status,
                      style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 8),
                Text(
                  '$total',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
