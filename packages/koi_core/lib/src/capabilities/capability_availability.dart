/// A value returned by a real adapter or module preflight, never a promise that
/// an operation will succeed. Callers must still handle execution errors.
enum CapabilityStatus { available, unavailable, unsupported }

final class CapabilityAvailability {
  const CapabilityAvailability.available()
    : status = CapabilityStatus.available,
      reason = null,
      diagnostic = null;
  const CapabilityAvailability.unavailable(String reason, {this.diagnostic})
    : reason = reason,
      assert(reason != ''),
      status = CapabilityStatus.unavailable;
  const CapabilityAvailability.unsupported(String reason)
    : reason = reason,
      assert(reason != ''),
      status = CapabilityStatus.unsupported,
      diagnostic = null;

  final CapabilityStatus status;

  /// Human-readable explanation suitable for a capability's recovery UI.
  final String? reason;

  /// Optional original failure for diagnostics; not automatically shown to users.
  final Object? diagnostic;
  bool get isAvailable => status == CapabilityStatus.available;
}
