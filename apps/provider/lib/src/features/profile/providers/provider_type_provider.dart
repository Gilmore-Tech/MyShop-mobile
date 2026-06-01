import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The provider role currently active in the app.
enum ProviderType {
  driver,
  artisan;

  bool get isDriver => this == ProviderType.driver;
  bool get isArtisan => this == ProviderType.artisan;
}

/// Single source of truth for which provider role the account-settings flow
/// should render. Defaults to driver until role-picker is implemented.
final providerTypeProvider =
    StateProvider<ProviderType>((_) => ProviderType.artisan);
