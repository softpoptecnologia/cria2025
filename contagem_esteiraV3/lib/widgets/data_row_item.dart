// data_row_item.dart
import 'package:flutter/material.dart';

class DataRowItem extends StatelessWidget {
  final String label;
  final IconData icon;

  const DataRowItem({super.key, required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(icon,
              size: 18,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
          const SizedBox(width: 8),
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
