import 'dart:convert';

import 'package:athena/decision.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('one yes/no question per request, in the /v1/systemone shape', () {
    final q = quickQuestions[1];
    expect(jsonDecode(decisionRequest('Win a prize!', q)), {
      'state': 'Win a prize!',
      'questions': {
        'answer': {'type': 'noul', 'instructions': q.instructions},
      },
    });
  });

  test('reads p(yes) from the answer', () {
    expect(readYesProbability('{"model":"m","answers":{"answer":{"noul":0.97}},"usage":{"input_tokens":40}}'), 0.97);
  });

  test('errors become something a person can act on', () {
    expect(() => readYesProbability('{"error":{"message":"the request exceeds the context size"}}'),
        throwsA(isA<DecisionError>().having((e) => e.message, 'message', contains('too long'))));
    expect(() => readYesProbability('not json'), throwsA(isA<DecisionError>()));
    expect(() => readYesProbability('{"answers":{}}'), throwsA(isA<DecisionError>()));
  });

  test('headline says how sure, not just which way', () {
    Verdict v(double p) => Verdict(question: quickQuestions.first, yesProbability: p, elapsed: Duration.zero);
    expect(v(0.97).headline, 'YES');
    expect(v(0.97).surePercent, 97);
    expect(v(0.03).headline, 'NO');
    expect(v(0.03).surePercent, 97);
    expect(v(0.7).headline, 'Probably yes');
    expect(v(0.3).headline, 'Probably no');
    expect(v(0.52).headline, "Can't tell");
  });

  test('a typed question gets its question mark', () {
    expect(customQuestion('  is it from my bank ').label, 'is it from my bank?');
    expect(customQuestion('Is it from my bank?').instructions, 'Is it from my bank?');
  });
}
