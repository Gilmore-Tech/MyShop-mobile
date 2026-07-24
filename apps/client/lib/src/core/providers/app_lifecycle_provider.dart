import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// True only while the client app is resumed and visible.
///
/// REST safety-net pollers watch or read this authority so an app that remains
/// mounted in the background does not keep consuming API capacity. Push
/// notifications and socket recovery remain the background/resume paths.
final appForegroundedProvider = StateProvider<bool>((_) => true);

bool isForegroundLifecycleState(AppLifecycleState state) {
  return state == AppLifecycleState.resumed;
}
