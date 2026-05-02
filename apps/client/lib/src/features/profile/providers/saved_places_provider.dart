import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/services/google_places_service.dart';

// ── Place Type ────────────────────────────────────────────────────────────────

enum PlaceType { home, work, custom }

extension PlaceTypeX on PlaceType {
  IconData get icon => switch (this) {
        PlaceType.home => Icons.home_outlined,
        PlaceType.work => Icons.work_outline_rounded,
        PlaceType.custom => Icons.place_outlined,
      };
}

// ── Thumbnail Style ───────────────────────────────────────────────────────────

enum ThumbnailStyle { residential, urban, commercial }

// ── Quick Category ────────────────────────────────────────────────────────────

class QuickCategory {
  final String label;
  final IconData icon;
  const QuickCategory({required this.label, required this.icon});
}

const kQuickCategories = <QuickCategory>[
  QuickCategory(label: 'Gym', icon: Icons.fitness_center_outlined),
  QuickCategory(label: 'School', icon: Icons.school_outlined),
  QuickCategory(label: 'Parents', icon: Icons.favorite_border_rounded),
];

// ── Saved Place ───────────────────────────────────────────────────────────────

class SavedPlace {
  final String id;
  final String name;
  final PlaceType type;
  final String address;
  final String lastVisitedLabel;
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
  final bool isLoading;
  final bool isDeletingId;
  final String? deletingId;
  final String? errorMessage;

  const SavedPlacesState({
    this.places = const [],
    this.isLoading = false,
    this.isDeletingId = false,
    this.deletingId,
    this.errorMessage,
  });

  String get countLabel {
    final n = places.length;
    return '$n ${n == 1 ? 'PLACE' : 'PLACES'}';
  }

  SavedPlacesState copyWith({
    List<SavedPlace>? places,
    bool? isLoading,
    bool? isDeletingId,
    String? deletingId,
    String? errorMessage,
    bool clearError = false,
    bool clearDeleting = false,
  }) =>
      SavedPlacesState(
        places: places ?? this.places,
        isLoading: isLoading ?? this.isLoading,
        isDeletingId:
            clearDeleting ? false : (isDeletingId ?? this.isDeletingId),
        deletingId: clearDeleting ? null : (deletingId ?? this.deletingId),
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      );
}

// ── Helpers ───────────────────────────────────────────────────────────────────

PlaceType _parsePlaceType(String? raw) => switch (raw) {
      'home' => PlaceType.home,
      'work' => PlaceType.work,
      _ => PlaceType.custom,
    };

ThumbnailStyle _thumbnailFor(PlaceType type) => switch (type) {
      PlaceType.home => ThumbnailStyle.residential,
      PlaceType.work => ThumbnailStyle.urban,
      PlaceType.custom => ThumbnailStyle.commercial,
    };

String _relativeTime(String? iso) {
  if (iso == null) return 'Recently';
  final dt = DateTime.tryParse(iso);
  if (dt == null) return 'Recently';
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays == 1) return 'Yesterday';
  return '${diff.inDays} days ago';
}

SavedPlace _fromJson(Map<String, dynamic> json) {
  final type = _parsePlaceType(json['locationType'] as String?);
  return SavedPlace(
    id: json['id'] as String,
    name: (json['label'] as String? ?? '').toUpperCase(),
    type: type,
    address: json['addressText'] as String? ?? '',
    lastVisitedLabel: _relativeTime(json['lastUsedAt'] as String?),
    thumbnailStyle: _thumbnailFor(type),
  );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class SavedPlacesNotifier extends StateNotifier<SavedPlacesState> {
  SavedPlacesNotifier(this._ref) : super(const SavedPlacesState()) {
    _load();
  }

  final Ref _ref;

  Future<void> _load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final raw = await _ref.read(userServiceProvider).getSavedLocations();
      final places = raw.cast<Map<String, dynamic>>().map(_fromJson).toList();
      state = state.copyWith(places: places, isLoading: false);
    } catch (e) {
      developer.log('getSavedLocations error: $e', name: 'SavedPlaces');
      state = state.copyWith(
          isLoading: false, errorMessage: 'Could not load saved places');
    }
  }

  Future<void> reload() => _load();

  /// Resolves a Google Places suggestion to coordinates and POSTs it as a new
  /// saved location. Returns `null` on success, a user-facing error message
  /// on failure. The new place is prepended to the list optimistically once
  /// the POST returns so the screen reflects it immediately.
  ///
  /// [label] is the user-entered name ("Home", "Gym", "Mom's House" …).
  /// [locationType] is the backend enum: 'home' | 'work' | 'favourite' —
  /// derived by the sheet from the chosen label, never user-typed directly.
  Future<String?> addPlace({
    required String label,
    required String locationType,
    required PlaceSuggestion suggestion,
  }) async {
    try {
      final detail = await _ref
          .read(googlePlacesServiceProvider)
          .getPlaceDetail(suggestion.placeId);
      if (detail == null) {
        return "Couldn't fetch the location's details. Try a different place.";
      }
      final json = await _ref.read(userServiceProvider).createSavedLocation(
            label: label,
            locationType: locationType,
            latitude: detail.latitude,
            longitude: detail.longitude,
            addressText: detail.address,
          );
      // Prepend so the new place is visible at the top of the list.
      state = state.copyWith(
        places: [_fromJson(json), ...state.places],
        clearError: true,
      );
      return null;
    } catch (e) {
      developer.log('createSavedLocation error: $e', name: 'SavedPlaces');
      return 'Could not save place. Please try again.';
    }
  }

  /// PUT /users/me/saved-locations/:id with a new label only.
  /// Coordinates and address stay as-is — re-picking the location is a
  /// "delete and re-add" flow on the screen.
  Future<String?> renamePlace({
    required String id,
    required String label,
  }) async {
    try {
      final json = await _ref
          .read(userServiceProvider)
          .updateSavedLocation(id, label: label);
      // Replace the renamed place in-place so other fields (address, last
      // visited) are preserved without a full reload.
      final updated = _fromJson(json);
      state = state.copyWith(
        places: [
          for (final p in state.places)
            if (p.id == id) updated else p,
        ],
        clearError: true,
      );
      return null;
    } catch (e) {
      developer.log('updateSavedLocation error: $e', name: 'SavedPlaces');
      return 'Could not rename place. Please try again.';
    }
  }

  /// DELETE /users/me/saved-locations/:id
  Future<void> deletePlace(String id) async {
    if (state.isDeletingId) return;
    state =
        state.copyWith(isDeletingId: true, deletingId: id, clearError: true);
    try {
      await _ref.read(userServiceProvider).deleteSavedLocation(id);
      state = state.copyWith(
        places: state.places.where((p) => p.id != id).toList(),
        clearDeleting: true,
      );
    } catch (e) {
      developer.log('deleteSavedLocation error: $e', name: 'SavedPlaces');
      state = state.copyWith(
        clearDeleting: true,
        errorMessage: 'Could not remove place. Please try again.',
      );
    }
  }
}

final savedPlacesProvider =
    StateNotifierProvider.autoDispose<SavedPlacesNotifier, SavedPlacesState>(
  (ref) => SavedPlacesNotifier(ref),
);
