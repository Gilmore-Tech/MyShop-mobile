import 'dart:io';

import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';

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
    MobileClientMetadataLoader? metadataLoader,
  })  : _app = app,
        _onUpdateRequired = onUpdateRequired,
        _metadataLoader = metadataLoader;

  static const appHeader = 'X-MyShop-App';
  static const platformHeader = 'X-MyShop-Platform';
  static const buildHeader = 'X-MyShop-Build';
  static const updateRequiredCode = 'APP_UPDATE_REQUIRED';

  final MobileAppKind _app;
  final void Function(AppUpdateRequirement requirement) _onUpdateRequired;
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
  void onError(DioException error, ErrorInterceptorHandler handler) {
    final requirement = _parseRequirement(error.response);
    if (requirement != null) {
      _onUpdateRequired(requirement);
    }
    handler.next(error);
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
    String? message;
    Map<String, dynamic>? details;
    if (rawError is Map) {
      final error = Map<String, dynamic>.from(rawError);
      code = _string(error['code']);
      message = _string(error['message']);
      if (error['details'] is Map) {
        details = Map<String, dynamic>.from(error['details'] as Map);
      }
    } else {
      code = _string(rawError) ?? _string(envelope['code']);
      message = _string(envelope['message']);
      if (envelope['details'] is Map) {
        details = Map<String, dynamic>.from(envelope['details'] as Map);
      }
    }
    if (code != updateRequiredCode) return null;

    return AppUpdateRequirement(
      message: message ?? 'A newer version of MyShop is required to continue.',
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
