import 'package:flutter/material.dart';

import '../catalog.dart';
import '../controller.dart';
import 'common.dart';
import 'settings_screen.dart';

/// Everything before the first question: checking the phone, the one download, getting ready.
class SetupScreen extends StatelessWidget {
  const SetupScreen({super.key, required this.controller});

  final AthenaController controller;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = controller;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                const Text('🦉', textAlign: TextAlign.center, style: TextStyle(fontSize: 64)),
                const SizedBox(height: 8),
                Text('Athena', textAlign: TextAlign.center, style: text.displaySmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                  'Paste a message and ask: is it urgent? Is it a scam? Does it need a reply? '
                  'Athena answers yes or no, and how sure it is.',
                  textAlign: TextAlign.center,
                  style: text.bodyLarge,
                ),
                const SizedBox(height: 28),
                if (c.device != null) _PhoneCard(controller: c),
                const SizedBox(height: 24),
                ..._phase(context),
                const SizedBox(height: 28),
                const PrivacyNote(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _phase(BuildContext context) {
    final c = controller;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final m = c.model;
    Widget caption(String s, {Color? color}) =>
        Text(s, textAlign: TextAlign.center, style: text.bodyMedium?.copyWith(color: color ?? scheme.onSurfaceVariant));
    Widget otherModels() => c.fittingModels.length > 1
        ? TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsScreen(controller: c))),
            child: const Text('Choose a different model'),
          )
        : const SizedBox.shrink();

    switch (c.phase) {
      case Phase.starting:
        return [const Center(child: CircularProgressIndicator()), const SizedBox(height: 12), caption('Checking your phone…')];
      case Phase.unsupported:
        return [
          Icon(Icons.info_outline, color: scheme.error, size: 32),
          const SizedBox(height: 8),
          caption(c.message ?? 'Athena does not run on this phone.', color: scheme.onSurface),
        ];
      case Phase.needsDownload:
        final resumed = c.partial > 0;
        return [
          FilledButton.icon(
            onPressed: c.download,
            icon: const Icon(Icons.download_rounded),
            label: Text(resumed
                ? 'Continue download (${formatBytes(c.partial)} of ${m!.size})'
                : 'Download ${m!.name} (${m.size})'),
          ),
          const SizedBox(height: 12),
          caption('One download, then Athena works offline. Use Wi-Fi, and keep Athena open until it finishes.'),
          otherModels(),
        ];
      case Phase.downloading:
        final fraction = m == null ? 0.0 : c.received / m.bytes;
        return [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(value: fraction, minHeight: 14),
          ),
          const SizedBox(height: 12),
          caption('${formatBytes(c.received)} of ${m!.size} · ${(fraction * 100).floor()}%', color: scheme.onSurface),
          const SizedBox(height: 4),
          caption('Keep Athena open until it finishes.'),
          TextButton(onPressed: c.pauseDownload, child: const Text('Pause')),
        ];
      case Phase.verifying:
        return [
          ClipRRect(borderRadius: BorderRadius.circular(8), child: const LinearProgressIndicator(minHeight: 14)),
          const SizedBox(height: 12),
          caption('Checking the download…'),
        ];
      case Phase.loading:
        return [const Center(child: CircularProgressIndicator()), const SizedBox(height: 12), caption('Getting ready…')];
      case Phase.failed:
        return [
          caption(c.message ?? 'Something went wrong.', color: scheme.error),
          const SizedBox(height: 16),
          FilledButton(onPressed: c.retry, child: const Text('Try again')),
          otherModels(),
        ];
      case Phase.ready:
        return const [];
    }
  }
}

class _PhoneCard extends StatelessWidget {
  const _PhoneCard({required this.controller});

  final AthenaController controller;

  @override
  Widget build(BuildContext context) {
    final d = controller.device!;
    final m = controller.model;
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.smartphone),
              title: Text(d.name),
              subtitle: Text('${marketingRam(d.ramBytes)} of memory'),
            ),
            if (m != null)
              ListTile(
                leading: const Icon(Icons.psychology_outlined),
                title: Text(m.name),
                subtitle: Text(m.blurb),
              ),
          ],
        ),
      ),
    );
  }
}
