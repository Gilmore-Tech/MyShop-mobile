import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ── Place Type ────────────────────────────────────────────────────────────────
// EDD § User Module: saved_locations (1:N per client, PostGIS POINT).
// last_used_at is tracked at the DB level and drives ordering.

enum PlaceType { home, work, custom }

extension PlaceTypeX on PlaceType {
  IconData get icon => switch (this) {
        PlaceType.home   => Icons.home_outlined,
        PlaceType.work   => Icons.work_outline_rounded,
        PlaceType.custom => Icons.place_outlined,
      };
}

// ── Thumbnail Style ───────────────────────────────────────────────────────────
// Drives the CustomPainter used for each place card's map preview.

enum ThumbnailStyle { residential, urban, commercial }

// ── Quick Category ────────────────────────────────────────────────────────────

class QuickCategory {
  final String   label;
  final IconData icon;
  const QuickCategory({required this.label, required this.icon});
}

const kQuickCategories = <QuickCategory>[
  QuickCategory(label: 'Gym',     icon: Icons.fitness_center_outlined),
  QuickCategory(label: 'School',  icon: Icons.school_outlined),
  QuickCategory(label: 'Parents', icon: Icons.favorite_border_rounded),
];

// ── Saved Place ───────────────────────────────────────────────────────────────
// API shape: GET /v1/users/me/saved-locations
// Deletion: PUT /v1/users/me  { savedLocations: [...without deleted] }

class SavedPlace {
  final String         id;
  final String         name;
  final PlaceType      type;
  final String         address;
  final String         lastVisitedLabel;
  final ThumbnailStyle thumbnailStyle;

  const SavedPlace({
    required this.id,
    required this.name,
    required this.type,
    required this.address,
    required this.lastVisitedLabel,
    required this.thumbnailStyle,
  });
}

// ── Saved Places State ────────────────────────────────────────────────────────

class SavedPlacesState {
  final List<SavedPlace> places;
  final String           searchQuery;
  final bool             isDeletingId;
  final String?          deletingId;
  final String?          errorMessage;

  const SavedPlacesState({
    this.places       = const [],
    this.searchQuery  = '',
    this.isDeletingId = false,
    this.deletingId,
    this.errorMessage,
  });

  /// Live count label shown in the "3 PLACES" badge.
  String get countLabel {
    final n = places.length;
    return '$n ${n == 1 ? 'PLACE' : 'PLACES'}';
  }

  SavedPlacesState copyWith({
    List<SavedPlace>? places,
    String?           searchQuery,
    bool?             isDeletingId,
    String?           deletingId,
    String?           errorMessage,
    bool              clearError = false,
  }) =>
      SavedPlacesState(
        places:       places       ?? this.places,
        searchQuery:  searchQuery  ?? this.searchQuery,
        isDeletingId: isDeletingId ?? this.isDeletingId,
        deletingId:   deletingId   ?? this.deletingId,
        errorMessage:
            clearError ? null : (errorMessage ?? this.errorMessage),
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class SavedPlacesNotifier extends StateNotifier<SavedPlacesState> {
  SavedPlacesNotifier() : super(const SavedPlacesState()) {
    _load();
  }

  Future<void> _load() async {
    // TODO: GET /v1/users/me/saved-locations
    await Future.delayed(const Duration(milliseconds: 300));
    state = state.copyWith(places: _mockPlaces);
  }

  Future<void> reload() => _load();

  /// Remove a saved location.
  /// PUT /v1/users/me  { savedLocations: [...remaining] }
  Future<void> deletePlace(String id) async {
    if (state.isDeletingId) return;
    state = state.copyWith(isDeletingId: true, deletingId: id, clearError: true);
    // TODO: PUT /v1/users/me with updated saved locations list
    await Future.delayed(const Duration(milliseconds: 500));
    state = state.copyWith(
      places:       state.places.where((p) => p.id != id).toList(),
      isDeletingId: false,
      deletingId:   null,
    );
  }
}

final savedPlacesProvider =
    StateNotifierProvider.autoDispose<SavedPlacesNotifier, SavedPlacesState>(
  (_) => SavedPlacesNotifier(),
);

// ── Mock data ─────────────────────────────────────────────────────────────────

const _mockPlaces = <SavedPlace>[
  SavedPlace(
    id:               'LOC-1',
    name:             'HOME',
    type:             PlaceType.home,
    address:          'No. 45 Independence Avenue, Ridge, Accra, Ghana',
    lastVisitedLabel: '2 hours ago',
    thumbnailStyle:   ThumbnailStyle.residential,
  ),
  SavedPlace(
    id:               'LOC-2',
    name:             'WORK (STANDARD CHARTERED)',
    type:             PlaceType.work,
    address:          '87 Independence Ave, North Ridge, Accra, Ghana',
    lastVisitedLabel: 'Yesterday',
    thumbnailStyle:   ThumbnailStyle.urban,
  ),
  SavedPlace(
    id:               'LOC-3',
    name:             'GOLD COAST GYM',
    type:             PlaceType.custom,
    address:          'Off George Walker Bush Hwy, Accra, Ghana',
    lastVisitedLabel: '3 days ago',
    thumbnailStyle:   ThumbnailStyle.commercial,
  ),
];
