# Category Icons — Admin ↔ Mobile contract

A category's `iconName` (stored by the backend) must be a key in the mobile app's
`_categoryIconByName` map (`services_provider.dart`). The mobile app resolves it to
`Icons.<key>`; unknown names fall back to `Icons.miscellaneous_services`.

The admin icon picker is restricted to exactly the keys in
`lib/material-icons.ts`. **Both lists must stay in sync** — if a name exists in the
admin picker but not in the mobile map, the app shows the fallback icon.

## Mobile change required

Add the following entries to `_categoryIconByName` (these are the new icons added
to the admin picker beyond the original 29). Every key is a valid `Icons.<key>`.

```dart
// Trades, repair & construction
'construction': Icons.construction,
'engineering': Icons.engineering,
'pest_control': Icons.pest_control,
'roofing': Icons.roofing,
'hvac': Icons.hvac,
'design_services': Icons.design_services,
'architecture': Icons.architecture,
'hardware': Icons.hardware,
'lightbulb': Icons.lightbulb,
'power': Icons.power,
'water_damage': Icons.water_damage,

// Cleaning, laundry & personal care
'local_laundry_service': Icons.local_laundry_service,
'dry_cleaning': Icons.dry_cleaning,
'checkroom': Icons.checkroom,
'bathtub': Icons.bathtub,
'soap': Icons.soap,
'shower': Icons.shower,

// Home, furniture & appliances
'bed': Icons.bed,
'chair': Icons.chair,
'weekend': Icons.weekend,
'microwave': Icons.microwave,
'blender': Icons.blender,
'coffee_maker': Icons.coffee_maker,
'window': Icons.window,
'fireplace': Icons.fireplace,
'countertops': Icons.countertops,

// Security
'security': Icons.security,
'key': Icons.key,
'doorbell': Icons.doorbell,
'sensors': Icons.sensors,
'videocam': Icons.videocam,
'garage': Icons.garage,

// Vehicles & transport
'directions_car': Icons.directions_car,
'local_car_wash': Icons.local_car_wash,
'directions_bike': Icons.directions_bike,
'two_wheeler': Icons.two_wheeler,
'electric_scooter': Icons.electric_scooter,
'local_taxi': Icons.local_taxi,
'agriculture': Icons.agriculture,

// Food & catering
'fastfood': Icons.fastfood,
'local_cafe': Icons.local_cafe,
'local_bar': Icons.local_bar,
'cake': Icons.cake,
'restaurant_menu': Icons.restaurant_menu,
'bakery_dining': Icons.bakery_dining,
'set_meal': Icons.set_meal,

// Shops & nature
'store': Icons.store,
'storefront': Icons.storefront,
'shopping_bag': Icons.shopping_bag,
'local_grocery_store': Icons.local_grocery_store,
'local_mall': Icons.local_mall,
'park': Icons.park,
'forest': Icons.forest,

// Health & care
'medical_services': Icons.medical_services,
'healing': Icons.healing,
'vaccines': Icons.vaccines,
'child_care': Icons.child_care,
'elderly': Icons.elderly,
'school': Icons.school,
'menu_book': Icons.menu_book,

// Creative, events & media
'music_note': Icons.music_note,
'piano': Icons.piano,
'palette': Icons.palette,
'photo_camera': Icons.photo_camera,
'movie': Icons.movie,
'celebration': Icons.celebration,
'event': Icons.event,
'card_giftcard': Icons.card_giftcard,

// Finance & business
'payments': Icons.payments,
'account_balance': Icons.account_balance,
'work': Icons.work,
'business_center': Icons.business_center,
'badge': Icons.badge,
'gavel': Icons.gavel,

// Comms & support
'translate': Icons.translate,
'language': Icons.language,
'support_agent': Icons.support_agent,
'call': Icons.call,
'mail': Icons.mail,

// Fitness & sport
'fitness_center': Icons.fitness_center,
'pool': Icons.pool,
'sports_soccer': Icons.sports_soccer,

// Tech
'print': Icons.print,
'router': Icons.router,
```

## Notes
- The original 29 entries are unchanged — no action needed for those.
- If your Flutter version is missing any `Icons.<name>` above, drop that one line
  from the map **and** remove the matching string from `lib/material-icons.ts` so
  the two stay aligned.
- Outlined variants in the original set (`build_outlined`,
  `home_repair_service_outlined`) already map to `Icons.build_outlined` /
  `Icons.home_repair_service_outlined`.
