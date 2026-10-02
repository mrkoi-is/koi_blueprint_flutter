/// Selection follows identity across filtering and reordering, never row offsets.
final class IdSelection {
  IdSelection({Set<String> ids = const {}, this.anchor})
    : ids = Set.unmodifiable(ids);
  final Set<String> ids;
  final String? anchor;

  IdSelection toggle(
    String id,
    List<String> visible, {
    bool range = false,
    bool additive = false,
  }) {
    if (!visible.contains(id)) return this;
    final start = anchor == null ? -1 : visible.indexOf(anchor!);
    if (range && start >= 0) {
      final end = visible.indexOf(id);
      final selected = visible.sublist(
        start < end ? start : end,
        (start > end ? start : end) + 1,
      );
      return IdSelection(
        ids: {...(additive ? ids : <String>{}), ...selected},
        anchor: anchor,
      );
    }
    return IdSelection(
      ids: ids.contains(id) ? ({...ids}..remove(id)) : {...ids, id},
      anchor: id,
    );
  }

  IdSelection selectAll(Iterable<String> visible) =>
      IdSelection(ids: {...ids, ...visible}, anchor: anchor);
  IdSelection retain(Iterable<String> existing) {
    final allowed = existing.toSet();
    return IdSelection(
      ids: ids.intersection(allowed),
      anchor: allowed.contains(anchor) ? anchor : null,
    );
  }
}
