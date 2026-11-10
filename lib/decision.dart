/// Questions in, a yes or no out: the /v1/systemone request for one yes/no ("noul") question,
/// and the verdict read back from the answer.
library;

import 'dart:convert';
import 'dart:math' as math;

class QuickQuestion {
  const QuickQuestion(this.label, this.instructions);

  /// What the button says.
  final String label;

  /// What the model is asked.
  final String instructions;
}

const quickQuestions = [
  QuickQuestion('Is it urgent?', 'Is this message urgent, so that it needs attention today?'),
  QuickQuestion('Is it a scam?', 'Is this message a scam or a phishing attempt?'),
  QuickQuestion('Does it need a reply?', 'Does this message need a reply?'),
  QuickQuestion('Is it friendly?', 'Is the tone of this message friendly or positive?'),
];

/// A question the user typed. "is it from my bank" → "is it from my bank?"
QuickQuestion customQuestion(String text) {
  var q = text.trim();
  if (q.isNotEmpty && !q.endsWith('?')) q = '$q?';
  return QuickQuestion(q, q);
}

String decisionRequest(String text, QuickQuestion question) => jsonEncode({
      'state': text,
      'questions': {
        'answer': {'type': 'noul', 'instructions': question.instructions},
      },
    });

class Verdict {
  Verdict({required this.question, required this.yesProbability, required this.elapsed});

  final QuickQuestion question;
  final double yesProbability;
  final Duration elapsed;

  bool get yes => yesProbability >= 0.5;

  /// How sure, of the answer it gave: 0.5 to 1.
  double get sureness => math.max(yesProbability, 1 - yesProbability);
  int get surePercent => (sureness * 100).round();

  /// "YES", "Probably no", "Can't tell"
  String get headline {
    if (sureness >= 0.8) return yes ? 'YES' : 'NO';
    if (sureness >= 0.6) return yes ? 'Probably yes' : 'Probably no';
    return "Can't tell";
  }
}

class DecisionError implements Exception {
  DecisionError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The probability of yes from the library's answer JSON. Throws [DecisionError] with something a
/// person can act on.
double readYesProbability(String answerJson) {
  final Object? decoded;
  try {
    decoded = jsonDecode(answerJson);
  } on FormatException {
    throw DecisionError('The model gave an answer Athena could not read.');
  }
  if (decoded is! Map<String, Object?>) throw DecisionError('The model gave an answer Athena could not read.');
  final error = decoded['error'];
  if (error != null) {
    final message = error is Map ? '${error['message']}' : '$error';
    if (RegExp('context|too long|exceed', caseSensitive: false).hasMatch(message)) {
      throw DecisionError('That text is too long for this phone. Try a shorter piece.');
    }
    throw DecisionError('The model could not answer: $message');
  }
  final answer = (decoded['answers'] as Map?)?['answer'];
  final p = answer is Map ? answer['noul'] : null;
  if (p is! num) throw DecisionError('The model gave an answer Athena could not read.');
  return p.toDouble().clamp(0.0, 1.0);
}
