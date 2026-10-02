import 'package:flutter_test/flutter_test.dart';
import 'package:workbench_app/features/workspace/domain/id_selection.dart';

void main() {
  test('selection survives filtering and reordering by entity identity', () {
    var selection = IdSelection().toggle('b', ['a', 'b', 'c']);
    selection = selection.toggle('a', ['c', 'a']);
    expect(selection.ids, {'a', 'b'});
    selection = selection.retain(['c', 'b']);
    expect(selection.ids, {'b'});
    expect(selection.anchor, isNull);
    expect(identical(selection.toggle('missing', ['b']), selection), isTrue);
  });
  test(
    'Shift range uses the current visible ordering and supports additive range',
    () {
      var selection = IdSelection().toggle('d', ['a', 'b', 'c', 'd']);
      selection = selection.toggle('b', ['d', 'c', 'b', 'a'], range: true);
      expect(selection.ids, {'d', 'c', 'b'});
      selection = selection.toggle(
        'a',
        ['a', 'b', 'c', 'd'],
        range: true,
        additive: true,
      );
      expect(selection.ids, {'a', 'b', 'c', 'd'});
      selection = selection.toggle('d', ['a', 'b', 'c', 'd']);
      expect(selection.ids, {'a', 'b', 'c'});
      expect(selection.selectAll(['z']).ids, {'a', 'b', 'c', 'z'});
      expect(() => selection.ids.add('illegal'), throwsUnsupportedError);
    },
  );
}
