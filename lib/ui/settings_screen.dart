import 'package:flutter/material.dart';

import '../catalog.dart';
import '../controller.dart';

/// The phone, the models that fit it, and the fine print.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.controller});

  final AthenaController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final c = controller;
    final d = c.device;
    if (d == null) return const SizedBox.shrink();
    final best = recommendedModel(d.ramBytes);
    final downloaded = c.downloadedModels;
    final leftovers = [
      for (final m in downloaded)
        if (!c.fittingModels.contains(m)) m,
    ];

    return ListView(
      children: [
        const _Header('This phone'),
        ListTile(
          leading: const Icon(Icons.smartphone),
          title: Text(d.name),
          subtitle: Text('${marketingRam(d.ramBytes)} of memory · ${d.isIOS ? 'iOS' : 'Android'} ${d.osVersion}'),
        ),
        const _Header('Model'),
        for (final m in c.fittingModels)
          ListTile(
            leading: Icon(m == c.model ? Icons.check_circle : Icons.circle_outlined,
                color: m == c.model ? Theme.of(context).colorScheme.primary : null),
            title: Text(m == best ? '${m.name} · best for this phone' : m.name),
            subtitle: Text('${m.blurb}\n${_status(c, m, downloaded.contains(m))}'),
            isThreeLine: true,
            onTap: m == c.model
                ? null
                : () {
                    c.useModel(m);
                    Navigator.of(context).pop();
                  },
            trailing: downloaded.contains(m)
                ? IconButton(
                    tooltip: 'Delete ${m.name}',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _confirmDelete(context, m),
                  )
                : null,
          ),
        if (leftovers.isNotEmpty) ...[
          const _Header('Downloaded, too big for this phone'),
          for (final m in leftovers)
            ListTile(
              title: Text(m.name),
              subtitle: Text(m.size),
              trailing: IconButton(
                tooltip: 'Delete ${m.name}',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _confirmDelete(context, m),
              ),
            ),
        ],
        const _Header('About'),
        const ListTile(
          leading: Icon(Icons.lock_outline),
          title: Text('Private'),
          subtitle: Text('Athena answers on your phone. It goes online only to download a model from Hugging Face.'),
        ),
        ExpansionTile(
          leading: const Icon(Icons.gavel_outlined),
          title: const Text('Model licenses'),
          children: [
            for (final m in catalog)
              ListTile(
                dense: true,
                title: Text('${m.name}: ${m.license}'),
                subtitle: SelectableText(m.licenseUrl),
              ),
          ],
        ),
        ListTile(
          leading: const Icon(Icons.description_outlined),
          title: const Text('Open-source licenses'),
          onTap: () => showLicensePage(
            context: context,
            applicationName: 'Athena',
            applicationLegalese: 'Decisions by kneejerk on llama.cpp. Models from Hugging Face, under their own licenses.',
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  String _status(AthenaController c, ModelInfo m, bool downloaded) {
    if (m == c.model && c.phase == Phase.ready) return 'In use · runs on the ${c.onGpu ? 'GPU' : 'CPU'} · ${m.size}';
    if (downloaded) return 'Downloaded · ${m.size}';
    return '${m.size} download';
  }

  Future<void> _confirmDelete(BuildContext context, ModelInfo m) async {
    final inUse = m == controller.model;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${m.name}?'),
        content: Text(inUse
            ? 'This frees ${m.size}. Athena needs a model to answer, so you will download one again.'
            : 'This frees ${m.size}.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await controller.delete(m);
    if (inUse && context.mounted) Navigator.of(context).pop();
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
    );
  }
}
