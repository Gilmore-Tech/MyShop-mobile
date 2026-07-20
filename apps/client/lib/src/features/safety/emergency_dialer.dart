import 'package:url_launcher/url_launcher.dart';

typedef EmergencyCanLaunch = Future<bool> Function(Uri uri);
typedef EmergencyLaunch = Future<bool> Function(Uri uri);

/// Opens the OS dialer without claiming that a call was placed or connected.
Future<bool> openEmergencyDialer(
  String phoneNumber, {
  EmergencyCanLaunch canLaunch = canLaunchUrl,
  EmergencyLaunch launch = _launchExternally,
}) async {
  final uri = Uri(scheme: 'tel', path: phoneNumber);
  if (!await canLaunch(uri)) return false;
  return launch(uri);
}

Future<bool> _launchExternally(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);
