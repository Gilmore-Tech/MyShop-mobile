import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/di/providers.dart';
import '../../../core/services/google_places_service.dart';
import '../../../core/providers/recent_locations_provider.dart';
import '../providers/edit_trip_provider.dart';
import '../providers/ride_search_provider.dart';

/// Sentinel passed via `GoRouterState.extra` to signal "create a new
/// intermediate stop" instead of editing an existing one.
const kNewStopSentinel = '__new_stop__';

// ── Screen ─────────────────────────────────────────────────────────────────────
// PRD § 4.3 — Client enters destination; coordinate-backed recents are shown.
// On selection → fare estimate screen.
// EDD: POST /v1/rides/estimate  { origin, destination }

class DestinationSearchScreen extends ConsumerStatefulWidget {
  final RideSearchField field;

  /// When non-null we're editing a trip stop (from the Edit Your Trip screen)
  /// rather than the pickup/destination on the fare-estimate flow. Pass the
  /// sentinel [kNewStopSentinel] to create a fresh intermediate stop.
  final String? stopId;

  const DestinationSearchScreen({
    super.key,
    this.field = RideSearchField.destination,
    this.stopId,
  });

  @override
  ConsumerState<DestinationSearchScreen> createState() =>
      _DestinationSearchScreenState();
}

class _DestinationSearchScreenState
    extends ConsumerState<DestinationSearchScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  List<PlaceSuggestion> _suggestions = [];
  bool _isLoading = false;
  Timer? _debounce;

  bool get _isPickup => widget.field == RideSearchField.pickup;
  bool get _isStopEdit => widget.stopId != null;
  bool get _hasQuery => _controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _suggestions = [];
        _isLoading = false;
      });
      return;
    }
    setState(() => _isLoading = true);
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final places = ref.read(googlePlacesServiceProvider);
      final results = await places.autocomplete(query);
      if (!mounted) return;
      setState(() {
        _suggestions = results;
        _isLoading = false;
      });
    });
  }

  Future<void> _selectSuggestion(PlaceSuggestion suggestion) async {
    setState(() => _isLoading = true);
    final places = ref.read(googlePlacesServiceProvider);
    final detail = await places.getPlaceDetail(suggestion.placeId);
    if (!mounted) return;

    if (detail != null) {
      if (detail.requiresExactPin) {
        setState(() => _isLoading = false);
        await _refineAreaSelection(detail);
        return;
      }
      _applyLocation(
        name: detail.name.isEmpty ? suggestion.mainText : detail.name,
        address: detail.address,
        lat: detail.latitude,
        lng: detail.longitude,
      );
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _refineAreaSelection(PlaceDetail detail) async {
    if (_isStopEdit) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Choose a specific address or use “Set location on map” for this stop.',
          ),
        ),
      );
      return;
    }

    // Keep the area's representative point only to centre the map. The fare
    // provider rejects `area` precision, so this coordinate can never produce
    // a misleading quote while the rider is choosing their exact point.
    ref.read(rideSearchProvider.notifier).setLocation(
          widget.field,
          RideLocation(
            name: detail.name,
            address: detail.address,
            lat: detail.latitude,
            lng: detail.longitude,
            precision: RideLocationPrecision.area,
          ),
        );

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Choose an exact point'),
        content: Text(
          '${detail.name} covers a wide area. Move the map pin to your exact '
          '${_isPickup ? 'pickup' : 'destination'} so the route and fare are accurate.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Continue to map'),
          ),
        ],
      ),
    );
    if (mounted) await _openPinPicker();
  }

  void _applyLocation({
    required String name,
    required String address,
    double? lat,
    double? lng,
  }) {
    if (_isStopEdit) {
      final stops = ref.read(tripStopsProvider.notifier);
      final fullAddress = '$name, $address';
      if (widget.stopId == kNewStopSentinel) {
        // Pass lat/lng so the confirm step can submit this row to the
        // backend without an extra round-trip — addStop on the API
        // requires real coords, not just the typed address.
        stops.addIntermediateStop(fullAddress, lat: lat, lng: lng);
      } else {
        stops.updateStopAddress(
          widget.stopId!,
          fullAddress,
          lat: lat,
          lng: lng,
        );
      }
    } else {
      ref.read(rideSearchProvider.notifier).setLocation(
            widget.field,
            RideLocation(name: name, address: address, lat: lat, lng: lng),
          );
    }
    if (lat != null && lng != null) {
      // Fire-and-forget — recents persistence shouldn't block navigation.
      ref
          .read(recentLocationsProvider.notifier)
          .add(name: name, address: address, lat: lat, lng: lng);
    }
    if (context.canPop()) context.pop();
  }

  Future<void> _openPinPicker() async {
    final fieldArg = _isPickup ? 'pickup' : 'destination';

    final confirmed = await context.push<bool>(
      AppRoutes.ridePinPickerPath(fieldArg),
      extra: widget.stopId,
    );

    if (!mounted || confirmed != true) return;

    // For stop edits the trip provider handles state; close the search screen
    // too so the rider returns to Plan Your Trip with the selected stop shown.
    if (_isStopEdit) {
      if (context.canPop()) context.pop();
      return;
    }

    final newSearch = ref.read(rideSearchProvider);
    final newLat =
        _isPickup ? newSearch.pickup?.lat : newSearch.destination?.lat;

    // Map picker confirmed a new location — close the search screen too so the
    // user lands back on the fare estimate screen with the field already filled.
    final picked = _isPickup ? newSearch.pickup : newSearch.destination;
    if (newLat != null && picked?.isPrecise == true) {
      final pickedLat = picked?.lat;
      final pickedLng = picked?.lng;
      if (picked != null && pickedLat != null && pickedLng != null) {
        ref.read(recentLocationsProvider.notifier).add(
              name: picked.name,
              address: picked.address,
              lat: pickedLat,
              lng: pickedLng,
            );
      }
      if (context.canPop()) context.pop();
    }
  }

  void _selectRecent(RecentLocation r) {
    _applyLocation(name: r.name, address: r.address, lat: r.lat, lng: r.lng);
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      body: Column(
        children: [
          _SearchHeader(
            controller: _controller,
            focusNode: _focusNode,
            top: top,
            title: _isPickup ? 'Pickup location' : 'Where to?',
            hintText: _isPickup ? 'Search pickup' : 'Search destination',
            onChanged: _onSearchChanged,
            onBack: () => context.pop(),
          ),
          Expanded(
            child: _isLoading
                ? const _LoadingIndicator()
                : ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      // Map pin — set location manually
                      _ActionTile(
                        icon: Icons.my_location_rounded,
                        iconBg: MyShopColors.darkSlate,
                        title: 'Set location on map',
                        subtitle: 'Drop a pin to choose any location',
                        onTap: _openPinPicker,
                      ),

                      // When searching — show autocomplete results
                      if (_hasQuery) ...[
                        if (_suggestions.isEmpty)
                          _EmptySearch(query: _controller.text)
                        else
                          ..._suggestions.map(
                            (s) => _SuggestionTile(
                              suggestion: s,
                              onTap: () => _selectSuggestion(s),
                            ),
                          ),
                      ],

                      // Only coordinate-backed recents are actionable. The old
                      // static Home/Work placeholders carried addresses but no
                      // coordinates and could strand riders without a fare.
                      if (!_hasQuery) ...[
                        if (ref.watch(recentLocationsProvider).isNotEmpty) ...[
                          const _SectionLabel(label: 'RECENT'),
                          ...ref.watch(recentLocationsProvider).map(
                                (r) => _RecentLocationTile(
                                  recent: r,
                                  onTap: () => _selectRecent(r),
                                ),
                              ),
                        ],
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Search header ──────────────────────────────────────────────────────────────

class _SearchHeader extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final double top;
  final String title;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback onBack;

  const _SearchHeader({
    required this.controller,
    required this.focusNode,
    required this.top,
    required this.title,
    required this.hintText,
    required this.onChanged,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: MyShopColors.surfaceWhite,
      padding: EdgeInsets.fromLTRB(0, top, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Back + title
          Row(
            children: [
              IconButton(
                onPressed: onBack,
                icon: const Icon(
                  Icons.arrow_back,
                  color: MyShopColors.textPrimary,
                ),
              ),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: MyShopColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Search field
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: MyShopColors.surfaceGrey,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(width: 14),
                    const Icon(
                      Icons.search_rounded,
                      color: MyShopColors.textSecondary,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: controller,
                        focusNode: focusNode,
                        onChanged: onChanged,
                        maxLines: 1,
                        style: const TextStyle(
                          color: MyShopColors.textPrimary,
                          fontSize: 16,
                        ),
                        decoration: InputDecoration(
                          hintText: hintText,
                          hintStyle: TextStyle(
                            color: MyShopColors.textSecondary.withAlpha(140),
                            fontSize: 16,
                          ),
                          border: InputBorder.none,
                          isDense: false,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    if (controller.text.isNotEmpty)
                      IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          controller.clear();
                          onChanged('');
                        },
                        icon: const Icon(
                          Icons.close_rounded,
                          color: MyShopColors.textSecondary,
                          size: 20,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tiles ──────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Text(
        label,
        style: const TextStyle(
          color: MyShopColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: MyShopColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: MyShopColors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tile for a Google Places autocomplete suggestion.
class _SuggestionTile extends StatelessWidget {
  final PlaceSuggestion suggestion;
  final VoidCallback onTap;

  const _SuggestionTile({
    required this.suggestion,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: MyShopColors.textSecondary.withAlpha(24),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.location_on_outlined,
                    color: MyShopColors.textSecondary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        suggestion.mainText,
                        style: const TextStyle(
                          color: MyShopColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (suggestion.secondaryText.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          suggestion.secondaryText,
                          style: const TextStyle(
                            color: MyShopColors.textSecondary,
                            fontSize: 14,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const Icon(
                  Icons.north_west_rounded,
                  color: MyShopColors.textSecondary,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
        Divider(
          height: 1,
          color: MyShopColors.divider,
          indent: 74,
        ),
      ],
    );
  }
}

/// Tile for a recently picked location.
class _RecentLocationTile extends StatelessWidget {
  final RecentLocation recent;
  final VoidCallback onTap;

  const _RecentLocationTile({
    required this.recent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: MyShopColors.textSecondary.withAlpha(24),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.history_rounded,
                    color: MyShopColors.textSecondary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        recent.name,
                        style: const TextStyle(
                          color: MyShopColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        recent.address,
                        style: const TextStyle(
                          color: MyShopColors.textSecondary,
                          fontSize: 14,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.north_west_rounded,
                  color: MyShopColors.textSecondary,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
        Divider(
          height: 1,
          color: MyShopColors.divider,
          indent: 74,
        ),
      ],
    );
  }
}

// ── Loading indicator ─────────────────────────────────────────────────────────

class _LoadingIndicator extends StatelessWidget {
  const _LoadingIndicator();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 32),
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: MyShopColors.primaryGold,
          ),
        ),
      ),
    );
  }
}

// ── Empty search ──────────────────────────────────────────────────────────────

class _EmptySearch extends StatelessWidget {
  final String query;
  const _EmptySearch({required this.query});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
      child: Column(
        children: [
          Icon(
            Icons.search_off_rounded,
            color: MyShopColors.textSecondary.withAlpha(80),
            size: 56,
          ),
          const SizedBox(height: 12),
          Text(
            'No results for "$query"',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MyShopColors.textSecondary,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}
