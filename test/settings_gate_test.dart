import 'package:flutter_test/flutter_test.dart';
import 'package:unplug/services/settings_gate.dart';

/// The direction table, in full.
///
/// This is the rule that decides whether a settings change costs the user a
/// wait, so it is tested as a table rather than through the pickers that call
/// it. Every cell here is a behaviour someone relies on: tightening a setting
/// has to stay free or the user cannot arm their own guard, and loosening one
/// has to ask or the gate is decorative.
void main() {
  group('a budget setting: the daily limit and the reward per wait', () {
    // More time for the same effort is the permissive direction. This is the
    // 40m -> 30m case the rule exists for: lowering a limit is the user
    // tightening their own guard and must never cost a wait.
    test('lowering it is free', () {
      expect(loosensBudget(40, 30), isFalse);
      expect(loosensBudget(30, 0), isFalse);
      expect(loosensBudget(3 * 60, 60), isFalse);
    });

    test('raising it asks', () {
      expect(loosensBudget(30, 40), isTrue);
      expect(loosensBudget(0, 30), isTrue);
      expect(loosensBudget(60, 5 * 60), isTrue);
    });

    // Re-saving the number that was already there is not a change. Without
    // this, a user who opens a picker, looks at it and saves pays a wait for
    // having decided to keep everything as it was.
    test('leaving it alone is not a change', () {
      expect(loosensBudget(30, 30), isFalse);
      expect(loosensBudget(0, 0), isFalse);
      expect(loosensBudget(5 * 60, 5 * 60), isFalse);
    });

    // Single-step moves are where an off-by-one in the comparison would hide.
    test('the boundary is one unit either way', () {
      expect(loosensBudget(30, 31), isTrue);
      expect(loosensBudget(31, 30), isFalse);
      expect(loosensBudget(30, 29), isFalse);
      expect(loosensBudget(29, 30), isTrue);
    });
  });

  group('a cost setting: the wait itself', () {
    // The wait is the price of a reward, so its permissive direction is
    // inverted. Making it longer is the user making the deal harder on
    // themselves — same effort, less reward — and that is free.
    test('lengthening it is free', () {
      expect(loosensCost(30, 60), isFalse);
      expect(loosensCost(60, 3 * 60), isFalse);
      expect(loosensCost(30, 31), isFalse);
    });

    // A shorter wait buys the same reward for less effort. That is the
    // loosening, so it is the one that asks.
    test('shortening it asks', () {
      expect(loosensCost(60, 30), isTrue);
      expect(loosensCost(3 * 60, 30), isTrue);
      expect(loosensCost(31, 30), isTrue);
    });

    test('leaving it alone is not a change', () {
      expect(loosensCost(30, 30), isFalse);
      expect(loosensCost(0, 0), isFalse);
    });
  });

  // The whole point of having two functions rather than one with a flag: the
  // two settings point opposite ways, and a single comparison applied to both
  // is exactly the bug this change exists to fix.
  //
  // They partition the directions rather than mirror each other. Every real
  // move loosens exactly one of the two shapes and neither of the other, and
  // a move that changes nothing loosens neither.
  test('the two shapes partition every direction between them', () {
    for (final from in [0, 30, 60]) {
      for (final to in [0, 30, 60]) {
        final budget = loosensBudget(from, to);
        final cost = loosensCost(from, to);
        if (from == to) {
          expect(budget, isFalse, reason: '$from -> $to changes nothing');
          expect(cost, isFalse, reason: '$from -> $to changes nothing');
        } else {
          expect(
            budget,
            isNot(cost),
            reason: 'a move from $from to $to must loosen exactly one of a '
                'budget and a cost, or the wait and the limit would gate '
                'opposite ways by accident rather than by design',
          );
        }
      }
    }
  });
}
