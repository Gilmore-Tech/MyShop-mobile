import 'dart:io';

import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/api_exception.dart';

enum MobileAppKind {
  client('client'),
  provider('provider');

  const MobileAppKind(this.headerValue);
  final String headerValue;
}

enum MobilePlatform {
  android('android'),
  ios('ios');

  const MobilePlatform(this.headerValue);
  final String headerValue;
}

/// A transient transport/service condition safe for app-owned UI.
///
/// This intentionally carries no backend prose.
enum MobileServiceIssue { offline, timeout, unavailable }

/// Converts only the legal-consent status request's explicit error into the
/// global notice model.
///
/// Ordinary HTTP failures are feature-owned and never pass through this
/// function. The app root calls it specifically for the authoritative legal
/// status provider, where a 5xx or malformed response must preserve the route
/// while explaining that revalidation is temporarily unavailable.
MobileServiceIssue? mobileServiceIssueForLegalStatusError(Object? error) {
  if (error is NetworkException) {
    return switch (error.kind) {
      NetworkFailureKind.offline => MobileServiceIssue.offline,
      NetworkFailureKind.timeout => MobileServiceIssue.timeout,
      NetworkFailureKind.unavailable => MobileServiceIssue.unavailable,
    };
  }
  return error == null ? null : MobileServiceIssue.unavailable;
}

/// Probes the public readiness endpoint and runs [onReady] only after a
/// successful HTTP response.
///
/// Apps use [onReady] to invalidate/revalidate legal consent. A failed probe
/// throws through to the caller and deliberately leaves the confirmed legal
/// snapshot and visible notice unchanged.
Future<void> probeMobileServiceReadiness(
  Dio dio, {
  required void Function() onReady,
}) async {
  final response = await dio.get<dynamic>(
    MobileClientInterceptor.readinessPath,
  );
  if (!_isHealthyReadinessResponse(response.data)) {
    throw const FormatException('Invalid service readiness response.');
  }
  onReady();
}

/// Accept only the backend's authenticated-by-shape public readiness contract.
///
/// A 200 status alone is insufficient: captive portals commonly answer every
/// request with HTML or their own JSON. Treating that as recovery would hide
/// the outage notice and re-run legal-consent routing against the wrong
/// service. The API's global response interceptor wraps the health payload in
/// `{success: true, data: ...}`, so require both dependency checks as well as
/// the healthy marker before announcing recovery.
bool _isHealthyReadinessResponse(Object? body) {
  if (body is! Map) return false;
  final envelope = Map<Object?, Object?>.from(body);
  if (envelope['success'] != true) return false;

  final rawData = envelope['data'];
  if (rawData is! Map) return false;
  final data = Map<Object?, Object?>.from(rawData);
  if (data['status'] != 'healthy') return false;

  final rawChecks = data['checks'];
  if (rawChecks is! Map) return false;
  final checks = Map<Object?, Object?>.from(rawChecks);
  return checks['database'] == 'ok' && checks['redis'] == 'ok';
}

class MobileClientMetadata {
  const MobileClientMetadata({
    required this.app,
    required this.platform,
    required this.buildNumber,
  });

  final MobileAppKind app;
  final MobilePlatform platform;
  final int buildNumber;
}

class AppUpdateRequirement {
  const AppUpdateRequirement({
    required this.message,
    this.app,
    this.platform,
    this.minimumBuild,
    this.currentBuild,
    this.storeUrl,
  });

  final String message;
  final MobileAppKind? app;
  final MobilePlatform? platform;
  final int? minimumBuild;
  final int? currentBuild;
  final Uri? storeUrl;
}

typedef MobileClientMetadataLoader = Future<MobileClientMetadata> Function();

/// Adds immutable app/platform/build metadata to first-party API requests and
/// surfaces the server's stable 426 contract to one app-owned update state.
class MobileClientInterceptor extends Interceptor {
  MobileClientInterceptor({
    required MobileAppKind app,
    required void Function(AppUpdateRequirement requirement) onUpdateRequired,
    void Function(MobileServiceIssue issue)? onServiceIssue,
    void Function()? onServiceRecovered,
    MobileClientMetadataLoader? metadataLoader,
  })  : _app = app,
        _onUpdateRequired = onUpdateRequired,
        _onServiceIssue = onServiceIssue,
        _onServiceRecovered = onServiceRecovered,
        _metadataLoader = metadataLoader;

  static const appHeader = 'X-MyShop-App';
  static const platformHeader = 'X-MyShop-Platform';
  static const buildHeader = 'X-MyShop-Build';
  static const updateRequiredCode = 'APP_UPDATE_REQUIRED';
  static const readinessPath = '/health/ready';
  static const safeUpdateMessage =
      'A newer version of MyShop is required to continue.';

  final MobileAppKind _app;
  final void Function(AppUpdateRequirement requirement) _onUpdateRequired;
  final void Function(MobileServiceIssue issue)? _onServiceIssue;
  final void Function()? _onServiceRecovered;
  final MobileClientMetadataLoader? _metadataLoader;
  Future<MobileClientMetadata>? _metadataFuture;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      final metadata = await (_metadataFuture ??= _loadMetadata());
      options.headers[appHeader] = metadata.app.headerValue;
      options.headers[platformHeader] = metadata.platform.headerValue;
      options.headers[buildHeader] = metadata.buildNumber.toString();
    } catch (_) {
      // A plugin failure must not take the whole app offline while the server
      // gate is dormant. Once activated, the backend rejects missing metadata
      // with the same non-dismissible 426 flow as an outdated build.
    }
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    // Recovery is explicit. A successful background poll or unrelated
    // feature request must not clear the outage notice or advance the legal
    // revalidation epoch. Only the user's public readiness probe may do so.
    if (response.requestOptions.path == readinessPath &&
        _isHealthyReadinessResponse(response.data)) {
      _onServiceRecovered?.call();
    }
    handler.next(response);
  }

  @override
  void onError(DioException error, ErrorInterceptorHandler handler) {
    final serviceIssue = _classifyServiceIssue(error);
    if (serviceIssue != null) {
      _onServiceIssue?.call(serviceIssue);
    }
    final requirement = _parseRequirement(error.response);
    if (requirement != null) {
      _onUpdateRequired(requirement);
    }
    handler.next(error);
  }

  MobileServiceIssue? _classifyServiceIssue(DioException error) {
    // Any trusted HTTP response belongs to the request's owning feature.
    // A document/payment/background-poll 5xx must never cover the whole app
    // with a global outage modal. Legal-consent failures are handled
    // explicitly by the legal gate, and a user retry probes readiness.
    if (error.response != null) return null;

    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.transformTimeout =>
        MobileServiceIssue.timeout,
      DioExceptionType.connectionError => MobileServiceIssue.offline,
      // Unknown no-response failures include malformed transport responses.
      // Keep the copy neutral instead of incorrectly blaming user consent.
      DioExceptionType.unknown ||
      DioExceptionType.badCertificate =>
        MobileServiceIssue.unavailable,
      // User/app cancellation is deliberate, not a connectivity incident.
      DioExceptionType.cancel || DioExceptionType.badResponse => null,
    };
  }

  Future<MobileClientMetadata> _loadMetadata() async {
    final customLoader = _metadataLoader;
    if (customLoader != null) return customLoader();

    final platform = Platform.isAndroid
        ? MobilePlatform.android
        : Platform.isIOS
            ? MobilePlatform.ios
            : throw UnsupportedError(
                'MyShop mobile metadata requires Android or iOS.',
              );
    final packageInfo = await PackageInfo.fromPlatform();
    final rawBuild = packageInfo.buildNumber.trim();
    if (!RegExp(r'^\d{1,10}$').hasMatch(rawBuild)) {
      throw const FormatException('Invalid mobile build number.');
    }
    final buildNumber = int.parse(rawBuild);
    return MobileClientMetadata(
      app: _app,
      platform: platform,
      buildNumber: buildNumber,
    );
  }

  AppUpdateRequirement? _parseRequirement(Response<dynamic>? response) {
    if (response?.statusCode != 426) return null;
    final body = response?.data;
    if (body is! Map) return null;
    final envelope = Map<String, dynamic>.from(body);
    final rawError = envelope['error'];

    String? code;
    Map<String, dynamic>? details;
    if (rawError is Map) {
      final error = Map<String, dynamic>.from(rawError);
      code = _string(error['code']);
      if (error['details'] is Map) {
        details = Map<String, dynamic>.from(error['details'] as Map);
      }
    } else {
      code = _string(rawError) ?? _string(envelope['code']);
      if (envelope['details'] is Map) {
        details = Map<String, dynamic>.from(envelope['details'] as Map);
      }
    }
    if (code != updateRequiredCode) return null;

    return AppUpdateRequirement(
      // The server controls only the stable machine contract and metadata.
      // Never render arbitrary response prose in a non-dismissible screen.
      message: safeUpdateMessage,
      app: _appKind(details?['app']),
      platform: _platform(details?['platform']),
      minimumBuild: _integer(details?['minimumBuild']),
      currentBuild: _integer(details?['currentBuild']),
      storeUrl: _safeStoreUri(details?['storeUrl']),
    );
  }

  String? _string(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  int? _integer(Object? value) => value is int && value >= 0 ? value : null;

  MobileAppKind? _appKind(Object? value) {
    final parsed = _string(value);
    for (final candidate in MobileAppKind.values) {
      if (candidate.headerValue == parsed) return candidate;
    }
    return null;
  }

  MobilePlatform? _platform(Object? value) {
    final parsed = _string(value);
    for (final candidate in MobilePlatform.values) {
      if (candidate.headerValue == parsed) return candidate;
    }
    return null;
  }

  Uri? _safeStoreUri(Object? value) {
    final parsed = Uri.tryParse(_string(value) ?? '');
    if (parsed == null || parsed.scheme != 'https' || parsed.host.isEmpty) {
      return null;
    }
    return parsed;
  }
}
