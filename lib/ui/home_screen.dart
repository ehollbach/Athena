import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller.dart';
import '../decision.dart';
import 'common.dart';
import 'settings_screen.dart';

/// Paste, tap a question, read the answer.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});

  final AthenaController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _text = TextEditingController();
  final _ownQuestions = <QuickQuestion>[];

  AthenaController get c => widget.controller;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _changed() {
    c.textChanged();
    setState(() {});
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final pasted = data?.text?.trim() ?? '';
    if (pasted.isEmpty) {
      _say('Nothing to paste. Copy a message first.');
      return;
    }
    _text.text = pasted;
    _changed();
  }

  void _ask(QuickQuestion q) {
    if (_text.text.trim().isEmpty) {
      _say('Paste or type a message first.');
      return;
    }
    FocusScope.of(context).unfocus();
    c.ask(_text.text, q);
  }

  Future<void> _askOwn() async {
    final typed = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const _OwnQuestionSheet(),
    );
    if (typed == null || typed.trim().isEmpty) return;
    final q = customQuestion(typed);
    setState(() {
      _ownQuestions.removeWhere((o) => o.label == q.label);
      _ownQuestions.insert(0, q);
    });
    _ask(q);
  }

  void _say(String s) =>
      ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(s)));

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Athena'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsScreen(controller: c))),
          ),
        ],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: c,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              TextField(
                controller: _text,
                onChanged: (_) => _changed(),
                minLines: 5,
                maxLines: 10,
                textCapitalization: TextCapitalization.sentences,
                style: text.bodyLarge,
                decoration: InputDecoration(
                  hintText: 'Paste a message, email or text here',
                  filled: true,
                  fillColor: scheme.surfaceContainerHigh,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
              ),
              Row(
                children: [
                  TextButton.icon(onPressed: _paste, icon: const Icon(Icons.content_paste), label: const Text('Paste')),
                  if (_text.text.isNotEmpty)
                    TextButton.icon(
                      onPressed: () {
                        _text.clear();
                        _changed();
                      },
                      icon: const Icon(Icons.clear),
                      label: const Text('Clear'),
                    ),
                ],
              ),
              if (c.isTooLong(_text.text))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'That is long: on this phone Athena reads the first ${c.model!.maxTextChars} characters.',
                    style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              const SizedBox(height: 8),
              Text('Ask', style: text.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final q in [...quickQuestions, ..._ownQuestions])
                    ActionChip(label: Text(q.label), onPressed: c.busy ? null : () => _ask(q)),
                  ActionChip(
                    avatar: const Icon(Icons.add),
                    label: const Text('Your own question'),
                    onPressed: c.busy ? null : _askOwn,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (c.busy) const _ThinkingCard(),
              if (c.askError != null)
                Card(
                  elevation: 0,
                  color: scheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(c.askError!, style: text.bodyLarge?.copyWith(color: scheme.onErrorContainer)),
                  ),
                ),
              for (final (i, v) in c.verdicts.indexed)
                i == 0 && !c.busy ? _VerdictCard(verdict: v) : _VerdictRow(verdict: v),
              const SizedBox(height: 24),
              const PrivacyNote(),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThinkingCard extends StatelessWidget {
  const _ThinkingCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: const Padding(
        padding: EdgeInsets.all(24),
        child: Row(
          children: [
            SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)),
            SizedBox(width: 16),
            Text('Thinking…', style: TextStyle(fontSize: 18)),
          ],
        ),
      ),
    );
  }
}

/// The latest answer, big.
class _VerdictCard extends StatelessWidget {
  const _VerdictCard({required this.verdict});

  final Verdict verdict;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final unsure = verdict.sureness < 0.6;
    return Card(
      elevation: 0,
      color: unsure ? scheme.surfaceContainerHigh : scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(verdict.question.label, style: text.titleMedium),
            const SizedBox(height: 4),
            Text(
              verdict.headline,
              style: text.displayMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: unsure ? scheme.onSurfaceVariant : scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${verdict.surePercent}% sure · ${_seconds(verdict.elapsed)}',
              style: text.bodyLarge?.copyWith(color: unsure ? scheme.onSurfaceVariant : scheme.onPrimaryContainer),
            ),
          ],
        ),
      ),
    );
  }
}

/// Earlier answers about the same text, small.
class _VerdictRow extends StatelessWidget {
  const _VerdictRow({required this.verdict});

  final Verdict verdict;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      title: Text(verdict.question.label),
      trailing: Text('${verdict.headline} · ${verdict.surePercent}%', style: text.titleMedium),
    );
  }
}

String _seconds(Duration d) => '${(d.inMilliseconds / 1000).toStringAsFixed(1)} s';

class _OwnQuestionSheet extends StatefulWidget {
  const _OwnQuestionSheet();

  @override
  State<_OwnQuestionSheet> createState() => _OwnQuestionSheetState();
}

class _OwnQuestionSheetState extends State<_OwnQuestionSheet> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Ask a yes or no question', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            controller: _q,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            onSubmitted: (v) => Navigator.of(context).pop(v),
            decoration: const InputDecoration(hintText: 'Is it from my bank?', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: () => Navigator.of(context).pop(_q.text), child: const Text('Ask')),
        ],
      ),
    );
  }
}
