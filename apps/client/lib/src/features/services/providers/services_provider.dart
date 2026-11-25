import 'package:api_client/api_client.dart' show Region;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/providers/current_operational_region_provider.dart';

// ── Service Category (UI model) ─────────────────────────────────────────────
// PRD 4.5: 10 categories seeded in DB. min_bid_pesewas configurable by admin.

class ServiceCategory {
  final String id;
  final String name;
  final IconData icon;
  final List<ServiceCategory>? children;

  const ServiceCategory({
    required this.id,
    required this.name,
    required this.icon,
    this.children,
  });

  bool get hasChildren => children != null && children!.isNotEmpty;
}

// ── Icon mapping ─────────────────────────────────────────────────────────────
//
// Categories are admin-managed (see admin CategoriesPage). The backend stores
// an [iconName] string per category drawn from a curated set; we resolve it to
// a Material [IconData] here. Adding a new admin-selectable icon means adding
// an entry to both [_categoryIconByName] below and the matching list in
// apps/admin/src/api/categories.ts (CATEGORY_ICONS).
//
// [_iconForSlug] provides icons for
// older categories that haven't been backfilled with an [iconName].

const Map<String, IconData> _categoryIconByName = {
  'handyman': Icons.handyman,
  'car_repair': Icons.car_repair,
  'electrical_services': Icons.electrical_services,
  'build_outlined': Icons.build_outlined,
  'content_cut': Icons.content_cut,
  'format_paint': Icons.format_paint,
  'home_repair_service_outlined': Icons.home_repair_service_outlined,
  'carpenter': Icons.carpenter,
  'plumbing': Icons.plumbing,
  'satellite_alt': Icons.satellite_alt,
  'laptop_mac': Icons.laptop_mac,
  'kitchen': Icons.kitchen,
  'tv': Icons.tv,
  'phone_android': Icons.phone_android,
  'ac_unit': Icons.ac_unit,
  'cleaning_services': Icons.cleaning_services,
  'local_shipping': Icons.local_shipping,
  'local_florist': Icons.local_florist,
  'pets': Icons.pets,
  'brush': Icons.brush,
  'lock': Icons.lock,
  'water_drop': Icons.water_drop,
  'bolt': Icons.bolt,
  'wifi': Icons.wifi,
  'computer': Icons.computer,
  'camera_alt': Icons.camera_alt,
  'restaurant': Icons.restaurant,
  'spa': Icons.spa,
  'miscellaneous_services': Icons.miscellaneous_services,
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
};

IconData _iconForSlug(String slug) {
  return switch (slug) {
    'towing' => Icons.local_shipping_outlined,
    'electrician' => Icons.electrical_services,
    'mechanic' => Icons.build_outlined,
    'seamstress' || 'fashion' || 'tailor' => Icons.content_cut,
    'painter' => Icons.format_paint,
    'masonry' || 'mason' => Icons.home_repair_service_outlined,
    'carpenter' => Icons.carpenter,
    'plumber' => Icons.plumbing,
    'satellite' || 'satellite-tv' || 'dish' => Icons.settings_input_antenna,
    'repairs' => Icons.handyman,
    'repair-laptop' || 'laptop-repair' => Icons.laptop_mac,
    'repair-fridge' || 'fridge-repair' => Icons.kitchen,
    'repair-tv' || 'tv-repair' => Icons.tv,
    'repair-phone' || 'phone-repair' => Icons.phone_android,
    'repair-ac' ||
    'ac-repair' ||
    'ac-services' ||
    'ac' =>
      Icons.ac_unit_rounded,
    'beautician' ||
    'beauty' ||
    'salon' ||
    'hair' ||
    'makeup' =>
      Icons.face_retouching_natural,
    'vulcanizer' || 'tire' || 'tyre' => Icons.tire_repair,
    'welder' || 'welding' => Icons.local_fire_department_outlined,
    'locksmith' => Icons.vpn_key_outlined,
    'cleaner' || 'cleaning' => Icons.cleaning_services_outlined,
    'gardener' || 'landscaper' || 'landscaping' => Icons.yard_outlined,
    'roofer' || 'roofing' => Icons.roofing,
    'mover' || 'movers' || 'moving' => Icons.moving_outlined,
    'security' || 'guard' => Icons.security,
    'pest' || 'fumigation' => Icons.pest_control_outlined,
    'tiler' || 'tiling' => Icons.grid_view_outlined,
    'barber' => Icons.content_cut_rounded,
    _ => Icons.miscellaneous_services,
  };
}

IconData _iconFor(String? iconName, String slug) {
  if (iconName != null && _categoryIconByName.containsKey(iconName)) {
    return _categoryIconByName[iconName]!;
  }
  return _iconForSlug(slug);
}

// ── Providers ─────────────────────────────────────────────────────────────────

final jobTownshipsProvider = FutureProvider<List<Region>>((ref) async {
  final regions = await ref.watch(regionServiceProvider).getRegions();
  return regions.where((region) => region.jobsEnabled).toList();
});

final selectedJobTownshipProvider = StateProvider<String?>((ref) => null);

final jobCatalogueTownshipProvider = FutureProvider<String?>((ref) async {
  final selected = ref.watch(selectedJobTownshipProvider);
  if (selected != null) return selected;
  final current = await ref.watch(currentOperationalRegionProvider.future);
  return current != null && current.jobsEnabled ? current.id : null;
});

final serviceCategoriesProvider =
    FutureProvider<List<ServiceCategory>>((ref) async {
  final service = ref.watch(categoryServiceProvider);
  final regionId = await ref.watch(jobCatalogueTownshipProvider.future);
  if (regionId == null) return const [];
  final apiCategories = await service.getCategories(regionId: regionId);

  return apiCategories.map((cat) {
    return ServiceCategory(
      id: cat.id,
      name: cat.name,
      icon: _iconFor(cat.iconName, cat.slug),
      children: cat.hasChildren
          ? cat.children
              .map((child) => ServiceCategory(
                    id: child.id,
                    name: child.name,
                    icon: _iconFor(child.iconName, child.slug),
                  ))
              .toList()
          : null,
    );
  }).toList();
});
