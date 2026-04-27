import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/di/providers.dart';
import '../../../core/services/google_places_service.dart';
import '../providers/edit_trip_provider.dart';
import '../providers/ride_search_provider.dart';

/// Sentinel passed via `GoRouterState.extra` to signal "create a new
/// intermediate stop" instead of editing an existing one.
const kNewStopSentinel = '__new_stop__';

// ── Saved places (static for now — will come from user profile API) ──────────

class _SavedPlace {
  final String name;
  final String address;
  final IconData icon;
  final Color iconBg;

  const _SavedPlace({
    required this.name,
    required this.address,
    required this.icon,
    required this.iconBg,
  });
}

const _savedPlaces = [
  _SavedPlace(
    name: 'Home',
    address: 'Suame, Kumasi',
    icon: Icons.home_rounded,
    iconBg: MyShopColors.info,
  ),
  _SavedPlace(
    name: 'Work',
    address: 'Adum Commercial Area, Kumasi',
    icon: Icons.work_rounded,
    iconBg: MyShopColors.success,
  ),
];

// ── Screen ─────────────────────────────────────────────────────────────────────
// PRD § 4.3 — Client enters destination; saved locations and recents shown.
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
      _applyLocation(
        name: suggestion.mainText,
        address: detail.address,
        lat: detail.latitude,
        lng: detail.longitude,
      );
    } else {
      setState(() => _isLoading = false);
    }
  }

  void _selectSavedPlace(_SavedPlace place) {
    // Saved places don't have coordinates yet — use name+address.
    // In production these will carry lat/lng from the user profile.
    _applyLocation(
      name: place.name,
      address: place.address,
    );
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
        stops.updateStopAddress(widget.stopId!, fullAddress, lat: lat, lng: lng);
      }
    } else {
      ref.read(rideSearchProvider.notifier).setLocation(
            widget.field,
            RideLocation(name: name, address: address, lat: lat, lng: lng),
          );
    }
    if (context.canPop()) context.pop();
  }

  Future<void> _openPinPicker() async {
    final fieldArg = _isPickup ? 'pickup' : 'destination';
    final search = ref.read(rideSearchProvider);
    final prevLat = _isPickup ? search.pickup?.lat : search.destination?.lat;

    await context.push<void>(
      AppRoutes.ridePinPickerPath(fieldArg),
      extra: widget.stopId,
    );

    // For stop edits the trip provider handles state — no need to pop.
    if (!mounted || _isStopEdit) return;

    final newSearch = ref.read(rideSearchProvider);
    final newLat = _isPickup ? newSearch.pickup?.lat : newSearch.destination?.lat;

    // Map picker confirmed a new location — close the search screen too so the
    // user lands back on the fare estimate screen with the field already filled.
    if (newLat != null && newLat != prevLat && context.canPop()) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;
    final top = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      body: Column(
        children: [
          _SearchHeader(
            controller: _controller,
            focusNode: _focusNode,
            top: top,
            w: w,
            h: h,
            title: _isPickup ? 'Pickup location' : 'Where to?',
            hintText: _isPickup ? 'Search pickup' : 'Search destination',
            onChanged: _onSearchChanged,
            onBack: () => context.pop(),
          ),
          Expanded(
            child: _isLoading
                ? _LoadingIndicator(w: w, h: h)
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
                        w: w,
                        h: h,
                      ),

                      // When searching — show autocomplete results
                      if (_hasQuery) ...[
                        if (_suggestions.isEmpty)
                          _EmptySearch(
                              query: _controller.text, w: w, h: h)
                        else
                          ..._suggestions.map((s) => _SuggestionTile(
                                suggestion: s,
                                onTap: () => _selectSuggestion(s),
                                w: w,
                                h: h,
                              )),
                      ],

                      // When idle — show saved + recent
                      if (!_hasQuery) ...[
                        _SectionLabel(label: 'SAVED PLACES', w: w),
                        ..._savedPlaces.map((p) => _SavedPlaceTile(
                              place: p,
                              onTap: () => _selectSavedPlace(p),
                              w: w,
                              h: h,
                            )),
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
  final double top, w, h;
  final String title;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback onBack;

  const _SearchHeader({
    required this.controller,
    required this.focusNode,
    required this.top,
    required this.w,
    required this.h,
    required this.title,
    required this.hintText,
    required this.onChanged,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: MyShopColors.surfaceWhite,
      padding: EdgeInsets.fromLTRB(0, top, w * 0.04, h * 0.016),
      child: Column(
        children: [
          // Back + title
          Row(
            children: [
              IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back,
                    color: MyShopColors.textPrimary),
              ),
              Text(
                title,
                style: TextStyle(
                  color: MyShopColors.textPrimary,
                  fontSize: w * 0.048,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          SizedBox(height: h * 0.008),
          // Search field
          Padding(
            padding: EdgeInsets.symmetric(horizontal: w * 0.04),
            child: Container(
              height: h * 0.058,
              decoration: BoxDecoration(
                color: MyShopColors.surfaceGrey,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  SizedBox(width: w * 0.04),
                  const Icon(Icons.search_rounded,
                      color: MyShopColors.textSecondary, size: 20),
                  SizedBox(width: w * 0.024),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      onChanged: onChanged,
                      style: TextStyle(
                          color: MyShopColors.textPrimary,
                          fontSize: w * 0.038),
                      decoration: InputDecoration(
                        hintText: hintText,
                        hintStyle: TextStyle(
                          color: MyShopColors.textSecondary.withAlpha(140),
                          fontSize: w * 0.036,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  if (controller.text.isNotEmpty)
                    IconButton(
                      onPressed: () {
                        controller.clear();
                        onChanged('');
                      },
                      icon: const Icon(Icons.close_rounded,
                          color: MyShopColors.textSecondary, size: 18),
                    ),
                ],
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
  final double w;
  const _SectionLabel({required this.label, required this.w});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(w * 0.05, w * 0.042, w * 0.05, w * 0.02),
      child: Text(
        label,
        style: TextStyle(
          color: MyShopColors.textSecondary,
          fontSize: w * 0.028,
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
  final double w, h;

  const _ActionTile({
    required this.icon,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: w * 0.05, vertical: h * 0.016),
        child: Row(
          children: [
            Container(
              width: w * 0.10,
              height: w * 0.10,
              decoration:
                  BoxDecoration(color: iconBg, shape: BoxShape.circle),
              child: Icon(icon, color: Colors.white, size: w * 0.050),
            ),
            SizedBox(width: w * 0.036),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: MyShopColors.textPrimary,
                          fontSize: w * 0.038,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          color: MyShopColors.textSecondary,
                          fontSize: w * 0.032)),
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
  final double w, h;

  const _SuggestionTile({
    required this.suggestion,
    required this.onTap,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: w * 0.05, vertical: h * 0.016),
            child: Row(
              children: [
                Container(
                  width: w * 0.10,
                  height: w * 0.10,
                  decoration: BoxDecoration(
                    color: MyShopColors.textSecondary.withAlpha(24),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.location_on_outlined,
                      color: MyShopColors.textSecondary, size: w * 0.048),
                ),
                SizedBox(width: w * 0.036),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        suggestion.mainText,
                        style: TextStyle(
                          color: MyShopColors.textPrimary,
                          fontSize: w * 0.038,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (suggestion.secondaryText.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          suggestion.secondaryText,
                          style: TextStyle(
                            color: MyShopColors.textSecondary,
                            fontSize: w * 0.032,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const Icon(Icons.north_west_rounded,
                    color: MyShopColors.textSecondary, size: 16),
              ],
            ),
          ),
        ),
        Divider(
          height: 1,
          color: MyShopColors.divider,
          indent: w * 0.05 + w * 0.10 + w * 0.036,
        ),
      ],
    );
  }
}

/// Tile for a saved place (Home, Work, etc.).
class _SavedPlaceTile extends StatelessWidget {
  final _SavedPlace place;
  final VoidCallback onTap;
  final double w, h;

  const _SavedPlaceTile({
    required this.place,
    required this.onTap,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: w * 0.05, vertical: h * 0.016),
            child: Row(
              children: [
                Container(
                  width: w * 0.10,
                  height: w * 0.10,
                  decoration: BoxDecoration(
                    color: place.iconBg.withAlpha(24),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(place.icon,
                      color: place.iconBg, size: w * 0.048),
                ),
                SizedBox(width: w * 0.036),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(place.name,
                          style: TextStyle(
                              color: MyShopColors.textPrimary,
                              fontSize: w * 0.038,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(place.address,
                          style: TextStyle(
                              color: MyShopColors.textSecondary,
                              fontSize: w * 0.032)),
                    ],
                  ),
                ),
                const Icon(Icons.north_west_rounded,
                    color: MyShopColors.textSecondary, size: 16),
              ],
            ),
          ),
        ),
        Divider(
          height: 1,
          color: MyShopColors.divider,
          indent: w * 0.05 + w * 0.10 + w * 0.036,
        ),
      ],
    );
  }
}

// ── Loading indicator ─────────────────────────────────────────────────────────

class _LoadingIndicator extends StatelessWidget {
  final double w, h;
  const _LoadingIndicator({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: h * 0.05),
      child: Center(
        child: SizedBox(
          width: w * 0.056,
          height: w * 0.056,
          child: const CircularProgressIndicator(
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
  final double w, h;
  const _EmptySearch(
      {required this.query, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: h * 0.08),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded,
              color: MyShopColors.textSecondary.withAlpha(80),
              size: w * 0.14),
          SizedBox(height: h * 0.016),
          Text(
            'No results for "$query"',
            style: TextStyle(
                color: MyShopColors.textSecondary, fontSize: w * 0.038),
          ),
        ],
      ),
    );
  }
}
