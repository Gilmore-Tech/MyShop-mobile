import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:myshop_client/src/features/ride/screens/destination_search_screen.dart';

// ─── Design Tokens ─────────────────────────────────────────────────────────────
// Source: CLAUDE.md §5.2 — will migrate to packages/shared_ui in Phase 6
const _kGold = Color(0xFFF5A623);
const _kDarkSlate = Color(0xFF46535D);
const _kDarkText = Color(0xFF161A1D);
const _kTextSecondary = Color(0xFF555E68);
const _kSurfaceGrey = Color(0xFFF3F5F6);
const _kOffWhite = Color(0xFFF6F7F8);

/// Home screen — map-first UI for ride booking and artisan services.
/// PRD Reference: §4.2 (Home Screen Architecture)
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  GoogleMapController? _mapController;
  int _navIndex = 0;

  // Kumasi Central Market — pilot city per PRD §1.1
  static const _kInitialCamera = CameraPosition(
    target: LatLng(6.6885, -1.6244),
    zoom: 14.0,
  );

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kOffWhite,
      body: Column(
        children: [
          _buildMapSection(),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  const _ActionCards(),
                  const SizedBox(height: 24),
                  const _SpecialOffersSection(),
                  const SizedBox(height: 24),
                  const _RecentPlacesSection(),
                  const SizedBox(height: 24),
                  const _VerifiedSafetyCard(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _HomeBottomNav(
        currentIndex: _navIndex,
        onTap: (i) => setState(() => _navIndex = i),
      ),
    );
  }

  Widget _buildMapSection() {
    return SizedBox(
      height: 280,
      child: Stack(
        fit: StackFit.expand,
        children: [
          GoogleMap(
            initialCameraPosition: _kInitialCamera,
            onMapCreated: (controller) => _mapController = controller,
            myLocationEnabled: true,
            zoomControlsEnabled: false,
            compassEnabled: false,
            myLocationButtonEnabled: false,
          ),
          const _MapGradient(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const _HeaderRow(),
                  _SearchCard(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const DestinationSearchScreen(),
                      ),
                    ),
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

// ─── Map Overlay ──────────────────────────────────────────────────────────────

class _MapGradient extends StatelessWidget {
  const _MapGradient();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0x73000000), Colors.transparent],
          begin: Alignment.topCenter,
          end: Alignment.center,
        ),
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.menu, color: _kDarkText, size: 20),
        ),
        const CircleAvatar(
          radius: 22,
          backgroundColor: _kSurfaceGrey,
          backgroundImage: NetworkImage('https://i.pravatar.cc/150?img=12'),
        ),
      ],
    );
  }
}

/// Tappable search card overlaid on the map — navigates to DestinationSearchScreen.
/// Displayed as read-only per the Uber/Bolt search bar pattern (PRD §4.3).
class _SearchCard extends StatelessWidget {
  const _SearchCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    // Current location indicator
                    Row(
                      children: [
                        Icon(Icons.circle, size: 10, color: _kGold),
                        SizedBox(width: 10),
                        Text(
                          'Current: Kumasi Central Market',
                          style: TextStyle(
                            color: _kGold,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Divider(height: 1, thickness: 1, color: Color(0xFFEEEEEE)),
                    ),
                    // Destination search row
                    Row(
                      children: [
                        Icon(Icons.search, color: _kTextSecondary, size: 18),
                        SizedBox(width: 10),
                        Text(
                          'Where are you going?',
                          style: TextStyle(color: _kTextSecondary, fontSize: 14),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const VerticalDivider(
                width: 1,
                thickness: 1,
                color: Color(0xFFE0E0E0),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.location_on_outlined, color: _kGold, size: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Action Cards ─────────────────────────────────────────────────────────────

class _ActionCards extends StatelessWidget {
  const _ActionCards();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _ServiceCard(
              icon: Icons.directions_car_filled,
              title: 'Book Ride',
              subtitle: 'Safe, verified drivers nearby',
              iconBackground: _kDarkSlate,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const DestinationSearchScreen(),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: _ServiceCard(
              icon: Icons.handyman,
              title: 'Artisan',
              subtitle: 'Hire pro help instantly',
              iconBackground: _kGold,
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.iconBackground,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color iconBackground;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: iconBackground,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              color: _kDarkText,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(color: _kTextSecondary, fontSize: 12),
          ),
          const SizedBox(height: 16),
          const Row(
            children: [
              Text(
                'Get started',
                style: TextStyle(color: _kTextSecondary, fontSize: 13),
              ),
              SizedBox(width: 4),
              Icon(Icons.arrow_forward_ios, size: 11, color: _kTextSecondary),
            ],
          ),
        ],
      ),
    ),
    );
  }
}

// ─── Special Offers ───────────────────────────────────────────────────────────

class _SpecialOffersSection extends StatelessWidget {
  const _SpecialOffersSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _SectionLabel(icon: Icons.card_giftcard, label: 'SPECIAL OFFERS'),
              _ViewAllButton(),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 150,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: const [
              _OfferCard(
                title: '20% Off Your First Ride',
                promoCode: 'AKWAABA',
              ),
              SizedBox(width: 12),
              _OfferCard(
                title: 'GHS 5 Off Your First Artisan Job',
                promoCode: 'SHOP5',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.title, required this.promoCode});

  final String title;
  final String promoCode;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 265,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF3D1A00), Color(0xFF1A0A00)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _kGold,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'SPECIAL OFFER',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Spacer(),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Use code: $promoCode',
            style: const TextStyle(color: _kGold, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ─── Recent Places ────────────────────────────────────────────────────────────

class _Place {
  const _Place(this.title, this.address);
  final String title;
  final String address;
}

class _RecentPlacesSection extends StatelessWidget {
  const _RecentPlacesSection();

  // Placeholder data — replaced by provider when API is wired
  // EDD §4: GET /v1/users/me/saved-locations
  static const _places = [
    _Place('Accra Mall', 'Tetteh Quarshie Interchange, Accra'),
    _Place('Home', '12 Garden Street, Kumasi'),
    _Place('University of Ghana', 'Legon Boundary Rd, Accra'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: _SectionLabel(icon: Icons.access_time, label: 'RECENT PLACES'),
        ),
        const SizedBox(height: 10),
        ...List.generate(_places.length, (i) {
          return _PlaceItem(
            title: _places[i].title,
            address: _places[i].address,
            showDivider: i < _places.length - 1,
            onTap: () {
              // TODO(MSP-XX): navigate to DestinationSearchScreen with pre-filled destination
            },
          );
        }),
      ],
    );
  }
}

class _PlaceItem extends StatelessWidget {
  const _PlaceItem({
    required this.title,
    required this.address,
    required this.showDivider,
    required this.onTap,
  });

  final String title;
  final String address;
  final bool showDivider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: _kSurfaceGrey,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.access_time,
                      size: 18,
                      color: _kTextSecondary,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: _kDarkText,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          address,
                          style: const TextStyle(
                            color: _kTextSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios,
                    size: 14,
                    color: _kTextSecondary,
                  ),
                ],
              ),
            ),
            if (showDivider)
              const Divider(height: 1, thickness: 1, color: Color(0xFFF0F0F0)),
          ],
        ),
      ),
    );
  }
}

// ─── Verified Safety Card ─────────────────────────────────────────────────────

class _VerifiedSafetyCard extends StatelessWidget {
  const _VerifiedSafetyCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: _kGold, width: 1.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          children: [
            _LightningIcon(),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Verified Safety Guaranteed',
                    style: TextStyle(
                      color: _kDarkText,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'All providers pass Ghana Police & KYC background checks.',
                    style: TextStyle(color: _kTextSecondary, fontSize: 12),
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

class _LightningIcon extends StatelessWidget {
  const _LightningIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: const Color(0x1AF5A623), // _kGold at 10% opacity
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.bolt, color: _kGold, size: 22),
    );
  }
}

// ─── Bottom Navigation ────────────────────────────────────────────────────────

class _HomeBottomNav extends StatelessWidget {
  const _HomeBottomNav({required this.currentIndex, required this.onTap});

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: currentIndex,
      onTap: onTap,
      type: BottomNavigationBarType.fixed,
      backgroundColor: Colors.white,
      selectedItemColor: _kGold,
      unselectedItemColor: _kDarkSlate,
      selectedLabelStyle: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.bold,
      ),
      unselectedLabelStyle: const TextStyle(fontSize: 10),
      elevation: 8,
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.near_me_outlined),
          activeIcon: Icon(Icons.near_me),
          label: 'Home',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.handyman_outlined),
          activeIcon: Icon(Icons.handyman),
          label: 'Services',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.access_time_outlined),
          activeIcon: Icon(Icons.access_time),
          label: 'Activity',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person_outline),
          activeIcon: Icon(Icons.person),
          label: 'Account',
        ),
      ],
    );
  }
}

// ─── Shared Section Components ────────────────────────────────────────────────

/// Section heading with a leading icon and uppercased overline label.
/// Typography: CLAUDE.md §5.3 — Overline: 10sp Black, 1.4 tracking
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: _kDarkText),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: _kDarkText,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
          ),
        ),
      ],
    );
  }
}

class _ViewAllButton extends StatelessWidget {
  const _ViewAllButton();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: null, // TODO(MSP-XX): wire up "View All offers" navigation
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'View All',
            style: TextStyle(
              color: _kGold,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(width: 4),
          Icon(Icons.arrow_forward_ios, size: 11, color: _kGold),
        ],
      ),
    );
  }
}
