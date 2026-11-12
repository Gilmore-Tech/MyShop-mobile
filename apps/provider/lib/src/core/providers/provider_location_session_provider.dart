import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const int providerLocationSequenceMax = 2147483647;

class ProviderLocationSessionState {
  const ProviderLocationSessionState({
    required this.onlineSessionId,
    required this.lastSequence,
    this.supportsSilentRecovery = false,
    this.backgroundLocationCredential,
  });

  final String onlineSessionId;
  final int lastSequence;
  final bool supportsSilentRecovery;
  final String? backgroundLocationCredential;

  ProviderLocationSessionState copyWith({required int lastSequence}) =>
      ProviderLocationSessionState(
        onlineSessionId: onlineSessionId,
        lastSequence: lastSequence,
        supportsSilentRecovery: supportsSilentRecovery,
        backgroundLocationCredential: backgroundLocationCredential,
      );
}

class ProviderLocationSessionController
    extends StateNotifier<ProviderLocationSessionState?> {
  ProviderLocationSessionController() : super(null);

  void install(String onlineSessionId, int lastSequence,
      {bool? supportsSilentRecovery, String? backgroundLocationCredential}) {
    final normalizedId = onlineSessionId.trim();
    if (normalizedId.isEmpty ||
        lastSequence < 0 ||
        lastSequence > providerLocationSequenceMax) {
      clear();
      throw const FormatException('Invalid provider location session');
    }
    final current = state;
    if (current?.onlineSessionId == normalizedId &&
        current!.lastSequence > lastSequence) {
      // An older reconciliation response must not rewind a sequence already
      // reserved by live socket/REST producers in this process. It may still
      // carry a renewed native credential, which must not be discarded.
      final renewedCredential = backgroundLocationCredential?.trim();
      if (renewedCredential != null &&
          renewedCredential.isNotEmpty &&
          renewedCredential != current.backgroundLocationCredential) {
        state = ProviderLocationSessionState(
          onlineSessionId: current.onlineSessionId,
          lastSequence: current.lastSequence,
          supportsSilentRecovery:
              supportsSilentRecovery ?? current.supportsSilentRecovery,
          backgroundLocationCredential: renewedCredential,
        );
      }
      return;
    }
    state = ProviderLocationSessionState(
      onlineSessionId: normalizedId,
      lastSequence: lastSequence,
      supportsSilentRecovery: supportsSilentRecovery ??
          (current?.onlineSessionId == normalizedId &&
              current!.supportsSilentRecovery),
      backgroundLocationCredential: backgroundLocationCredential ??
          (current?.onlineSessionId == normalizedId
              ? current!.backgroundLocationCredential
              : null),
    );
  }

  void installSnapshot(ProviderAvailabilitySnapshot snapshot) {
    final onlineSessionId = snapshot.onlineSessionId;
    final lastSequence = snapshot.lastLocationSequence;
    if (onlineSessionId == null || lastSequence == null) {
      clear();
      return;
    }
    install(onlineSessionId, lastSequence,
        supportsSilentRecovery: snapshot.sessionStatus != null,
        backgroundLocationCredential: snapshot.backgroundLocationCredential);
  }

  void installResponse(Map<String, dynamic> response) {
    final onlineSessionId = response['onlineSessionId']?.toString().trim();
    final rawSequence = response['lastLocationSequence'];
    final lastSequence = rawSequence is int
        ? rawSequence
        : rawSequence is num &&
                rawSequence.isFinite &&
                rawSequence == rawSequence.roundToDouble()
            ? rawSequence.toInt()
            : null;
    if (onlineSessionId == null ||
        onlineSessionId.isEmpty ||
        lastSequence == null) {
      clear();
      throw const FormatException('Missing provider location session');
    }
    final credential =
        response['backgroundLocationCredential']?.toString().trim();
    install(onlineSessionId, lastSequence,
        backgroundLocationCredential:
            credential == null || credential.isEmpty ? null : credential);
  }

  int nextSequence() {
    final current = state;
    if (current == null) {
      throw StateError('Provider location session is not established');
    }
    if (current.lastSequence >= providerLocationSequenceMax) {
      clear();
      throw StateError('Provider location sequence is exhausted');
    }
    final next = current.lastSequence + 1;
    state = current.copyWith(lastSequence: next);
    return next;
  }

  void clear() => state = null;
}

final providerLocationSessionProvider = StateNotifierProvider<
    ProviderLocationSessionController, ProviderLocationSessionState?>((ref) {
  return ProviderLocationSessionController();
});
