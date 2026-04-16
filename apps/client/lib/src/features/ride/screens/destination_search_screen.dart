import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../providers/edit_trip_provider.dart';
import '../providers/ride_search_provider.dart';

/// Sentinel passed via `GoRouterState.extra` to signal "create a new
/// intermediate stop" instead of editing an existing one.
const kNewStopSentinel = '__new_stop__';

// ── Mock data ──────────────────────────────────────────────────────────────────

class _Place {
  final String name;
  final String address;
  final IconData icon;
  final Color iconBg;

  const _Place({
    required this.name,
    required this.address,
    required this.icon,
    required this.iconBg,
  });
}

const _savedPlaces = [
  _Place(
    name:   'Home',
    address: 'Suame, Kumasi',
    icon:   Icons.home_rounded,
    iconBg: MyShopColors.info,
  ),
  _Place(
    name:   'Work',
    address: 'Adum Commercial Area, Kumasi',
    icon:   Icons.work_rounded,
    iconBg: MyShopColors.success,
  ),
];

const _recentPlaces = [
  _Place(
    name:    'Kumasi City Mall',
    address: 'Lake Road, Suame',
    icon:    Icons.history_rounded,
    iconBg:  MyShopColors.textSecondary,
  ),
  _Place(
    name:    'Kejetia Market',
    address: 'Central Kumasi',
    icon:    Icons.history_rounded,
    iconBg:  MyShopColors.textSecondary,
  ),
  _Place(
    name:    'Kotoko Stadium',
    address: 'Bantama, Kumasi',
    icon:    Icons.history_rounded,
    iconBg:  MyShopColors.textSecondary,
  ),
  _Place(
    name:    'Komfo Anokye Teaching Hospital',
    address: 'Bantama Road, Kumasi',
    icon:    Icons.history_rounded,
    iconBg:  MyShopColors.textSecondary,
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
  final _controller  = TextEditingController();
  final _focusNode   = FocusNode();
  String _query = '';

  bool get _isPickup => widget.field == RideSearchField.pickup;
  bool get _isStopEdit => widget.stopId != null;

  // Simple client-side filter — replace with Google Places API call.
  List<_Place> get _filteredRecents => _query.isEmpty
      ? _recentPlaces
      : _recentPlaces
          .where((p) =>
              p.name.toLowerCase().contains(_query.toLowerCase()) ||
              p.address.toLowerCase().contains(_query.toLowerCase()))
          .toList();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _selectPlace(_Place place) {
    final fullAddress = '${place.name}, ${place.address}';
    if (_isStopEdit) {
      final stops = ref.read(tripStopsProvider.notifier);
      if (widget.stopId == kNewStopSentinel) {
        stops.addIntermediateStop(fullAddress);
      } else {
        stops.updateStopAddress(widget.stopId!, fullAddress);
      }
    } else {
      ref.read(rideSearchProvider.notifier).setLocation(
            widget.field,
            RideLocation(name: place.name, address: place.address),
          );
    }
    if (context.canPop()) context.pop();
  }

  void _openPinPicker() {
    final fieldArg =
        _isPickup ? 'pickup' : 'destination';
    // Forward the stopId so the pin picker writes back to the same target.
    context.push(
      AppRoutes.ridePinPickerPath(fieldArg),
      extra: widget.stopId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w    = size.width;
    final h    = size.height;
    final top  = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      body: Column(
        children: [
          _SearchHeader(
            controller:  _controller,
            focusNode:   _focusNode,
            top:         top,
            w:           w,
            h:           h,
            title:       _isPickup ? 'Pickup location' : 'Where to?',
            hintText:    _isPickup ? 'Search pickup' : 'Search destination',
            onChanged:   (v) => setState(() { _query = v; }),
            onBack:      () => context.pop(),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                // Map pin — set location manually
                _ActionTile(
                  icon:    Icons.my_location_rounded,
                  iconBg:  MyShopColors.darkSlate,
                  title:   'Set location on map',
                  subtitle:'Drop a pin to choose any location',
                  onTap:   _openPinPicker,
                  w: w, h: h,
                ),
                if (_query.isEmpty) ...[
                  _SectionLabel(label: 'SAVED PLACES', w: w),
                  ..._savedPlaces.map((p) => _PlaceTile(
                      place: p, onTap: () => _selectPlace(p), w: w, h: h)),
                  _SectionLabel(label: 'RECENT', w: w),
                ],
                if (_filteredRecents.isEmpty)
                  _EmptySearch(query: _query, w: w, h: h)
                else
                  ..._filteredRecents.map((p) => _PlaceTile(
                      place: p, onTap: () => _selectPlace(p), w: w, h: h)),
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
  final FocusNode             focusNode;
  final double                top, w, h;
  final String                title;
  final String                hintText;
  final ValueChanged<String>  onChanged;
  final VoidCallback          onBack;

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
                  color:      MyShopColors.textPrimary,
                  fontSize:   w * 0.048,
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
                color:        MyShopColors.surfaceGrey,
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
                      controller:  controller,
                      focusNode:   focusNode,
                      onChanged:   onChanged,
                      style: TextStyle(
                          color:    MyShopColors.textPrimary,
                          fontSize: w * 0.038),
                      decoration: InputDecoration(
                        hintText: hintText,
                        hintStyle: TextStyle(
                          color:    MyShopColors.textSecondary.withAlpha(140),
                          fontSize: w * 0.036,
                        ),
                        border:         InputBorder.none,
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
          color:         MyShopColors.textSecondary,
          fontSize:      w * 0.028,
          fontWeight:    FontWeight.w900,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color    iconBg;
  final String   title;
  final String   subtitle;
  final VoidCallback onTap;
  final double   w, h;

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
              width:  w * 0.10,
              height: w * 0.10,
              decoration: BoxDecoration(
                  color: iconBg, shape: BoxShape.circle),
              child: Icon(icon, color: Colors.white, size: w * 0.050),
            ),
            SizedBox(width: w * 0.036),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color:      MyShopColors.textPrimary,
                          fontSize:   w * 0.038,
                          fontWeight: FontWeight.w600)),
                  SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          color:    MyShopColors.textSecondary,
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

class _PlaceTile extends StatelessWidget {
  final _Place       place;
  final VoidCallback onTap;
  final double       w, h;

  const _PlaceTile({
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
                  width:  w * 0.10,
                  height: w * 0.10,
                  decoration: BoxDecoration(
                      color: place.iconBg.withAlpha(24),
                      shape: BoxShape.circle),
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
                              color:      MyShopColors.textPrimary,
                              fontSize:   w * 0.038,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(place.address,
                          style: TextStyle(
                              color:    MyShopColors.textSecondary,
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
        Divider(height: 1, color: MyShopColors.divider,
            indent: w * 0.05 + w * 0.10 + w * 0.036),
      ],
    );
  }
}

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
              color: MyShopColors.textSecondary.withAlpha(80), size: w * 0.14),
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
