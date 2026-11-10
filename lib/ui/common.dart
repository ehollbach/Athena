import 'package:flutter/material.dart';

/// The one line that says what Athena is about.
class PrivacyNote extends StatelessWidget {
  const PrivacyNote({super.key});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.lock_outline, size: 16, color: style?.color),
        const SizedBox(width: 6),
        Flexible(child: Text('Runs on your phone. What you paste never leaves it.', style: style)),
      ],
    );
  }
}
