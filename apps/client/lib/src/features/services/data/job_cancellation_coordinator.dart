import 'package:api_client/api_client.dart';

class JobCancellationResult {
  const JobCancellationResult._({
    required this.confirmedCancelled,
    required this.reconciled,
    required this.message,
    this.response = const <String, dynamic>{},
  });

  factory JobCancellationResult.cancelled(
    Map<String, dynamic> response, {
    bool reconciled = false,
  }) {
    return JobCancellationResult._(
      confirmedCancelled: true,
      reconciled: reconciled,
      message: 'Job request cancelled.',
      response: response,
    );
  }

  factory JobCancellationResult.notCancelled(String message) {
    return JobCancellationResult._(
      confirmedCancelled: false,
      reconciled: true,
      message: message,
    );
  }

  factory JobCancellationResult.unknown() {
    return const JobCancellationResult._(
      confirmedCancelled: false,
      reconciled: false,
      message:
          "We couldn't confirm whether the job was cancelled. Keep this request open while we check again.",
    );
  }

  final bool confirmedCancelled;
  final bool reconciled;
  final String message;
  final Map<String, dynamic> response;
}

Future<JobCancellationResult> cancelJobWithAuthority({
  required JobService jobService,
  required String jobId,
  required String reason,
}) async {
  Object? cancellationError;
  try {
    final response = await jobService.cancelJob(jobId, reason: reason);
    return JobCancellationResult.cancelled(response);
  } catch (error) {
    cancellationError = error;
  }

  try {
    final snapshot = await jobService.getJob(jobId);
    final status = snapshot['status']?.toString().trim().toLowerCase();
    if (status == 'cancelled' || status == 'canceled') {
      return JobCancellationResult.cancelled(
        const <String, dynamic>{},
        reconciled: true,
      );
    }
    return JobCancellationResult.notCancelled(
      _jobCancellationFailureMessage(cancellationError, status),
    );
  } catch (_) {
    return JobCancellationResult.unknown();
  }
}

String _jobCancellationFailureMessage(Object? error, String? status) {
  if (status == 'in_progress' || status == 'artisan_marked_complete') {
    return 'This work has already started and can no longer be cancelled here.';
  }
  if (status == 'completed') {
    return 'This job has already been completed.';
  }
  final code = error is ApiException ? error.errorCode : null;
  return switch (code) {
    'JOB_NOT_FOUND' =>
      'This job could not be found. Refresh your activity and try again.',
    'NOT_YOUR_JOB' ||
    'CLIENT_PROFILE_REQUIRED' ||
    'PROFILE_REQUIRED' =>
      'This account is not allowed to cancel the job.',
    'JOB_NOT_CANCELLABLE' ||
    'INVALID_STATUS_TRANSITION' =>
      'This job can no longer be cancelled.',
    'RATE_LIMITED' ||
    'TOO_MANY_REQUESTS' =>
      'Too many attempts. Wait a moment, then try again.',
    _ => 'Could not cancel the request. Please try again.',
  };
}
