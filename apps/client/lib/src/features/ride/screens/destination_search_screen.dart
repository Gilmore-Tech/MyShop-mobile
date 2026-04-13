import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'driver_matching_screen.dart';

// ─── Design Tokens ─────────────────────────────────────────────────────────────
// Source: CLAUDE.md §5.2
const _kGold = Color(0xFFF5A623);
const _kDarkSlate = Color(0xFF46535D);
const _kDarkText = Color(0xFF161A1D);
const _kTextSecondary = Color(0xFF555E68);
const _kSurfaceGrey = Color(0xFFF3F5F6);
const _kOffWhite = Color(0xFFF6F7F8);

// ─── Local Data Models ────────────────────────────────────────────────────────

class _VehicleOption {
  const _VehicleOption({
    required this.id,
    required this.name,
    required this.description,
    required this.capacity,
    required this.fareGhs,
    required this.etaMinutes,
    required this.iconData,
  });

  final String id;
  final String name;
  final String description;
  final int capacity;
  final double fareGhs;
  final int etaMinutes;
  final IconData iconData;
}

// Placeholder vehicle options — wired to POST /v1/rides/estimate in Phase 2 (EDD §4)
const _kVehicles = [
  _VehicleOption(
    id: 'comfort',
    name: 'Ride Comfort',
    description: 'Newer cars with extra legroom',
    capacity: 4,
    fareGhs: 42.00,
    etaMinutes: 2,
    iconData: Icons.directions_car_filled,
  ),
  _VehicleOption(
    id: 'moto_standard',
    name: 'Moto-Ride',
    description: 'Beat the heavy Kumasi traffic',
    capacity: 1,
    fareGhs: 12.00,
    etaMinutes: 1,
    iconData: Icons.two_wheeler,
  ),
  _VehicleOption(
    id: 'moto_scooter',
    name: 'Moto-Ride',
    description: 'Beat the heavy Kumasi traffic',
    capacity: 1,
    fareGhs: 12.00,
    etaMinutes: 1,
    iconData: Icons.electric_moped,
  ),
];

class _RecentDestination {
  const _RecentDestination(this.label, this.sublabel, this.icon);
  final String label;
  final String sublabel;
  final IconData icon;
}

const _kRecentDestinations = [
  _RecentDestination('Home', 'Asokwa Residential', Icons.home_outlined),
  _RecentDestination('Office', 'Tech Hub, KNUST', Icons.work_outline),
];

// ─── Screen ───────────────────────────────────────────────────────────────────

/// Plan Your Trip screen — enter pickup/destination, select vehicle type, confirm.
/// PRD §4.3 | API: POST /v1/rides/estimate, POST /v1/rides (EDD §4)
class DestinationSearchScreen extends ConsumerStatefulWidget {
  const DestinationSearchScreen({super.key});

  @override
  ConsumerState<DestinationSearchScreen> createState() =>
      _DestinationSearchScreenState();
}

class _DestinationSearchScreenState
    extends ConsumerState<DestinationSearchScreen> {
  final _pickupController = TextEditingController(
    text: 'Kejetia Market, Kumasi',
  );
  final _destinationController = TextEditingController();
  String _selectedVehicleId = 'comfort';

  @override
  void dispose() {
    _pickupController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  void _onConfirmRide() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DriverMatchingScreen()),
    );
  }

  void _onCancelRequest() => Navigator.pop(context);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kOffWhite,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        leading: const BackButton(color: _kDarkText),
        title: const Text(
          'Plan Your Trip',
          style: TextStyle(
            color: _kDarkText,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: Colors.grey[200]!),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  _LocationInputCard(
                    pickupController: _pickupController,
                    destinationController: _destinationController,
                  ),
                  const SizedBox(height: 16),
                  const _RecentDestinationsSection(),
                  const SizedBox(height: 16),
                  const _SurgePricingBanner(),
                  const SizedBox(height: 20),
                  _VehicleSelectionSection(
                    vehicles: _kVehicles,
                    selectedId: _selectedVehicleId,
                    onSelect: (id) => setState(() => _selectedVehicleId = id),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
          _PaymentFooter(
            onConfirm: _onConfirmRide,
            onCancel: _onCancelRequest,
          ),
        ],
      ),
    );
  }
}

// ─── Location Input Card ──────────────────────────────────────────────────────

class _LocationInputCard extends StatelessWidget {
  const _LocationInputCard({
    required this.pickupController,
    required this.destinationController,
  });

  final TextEditingController pickupController;
  final TextEditingController destinationController;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left column: icons + dashed connector
            Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Icon(Icons.circle_outlined, color: _kGold, size: 18),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: CustomPaint(
                      painter: _DashedLinePainter(),
                      child: const SizedBox(width: 2),
                    ),
                  ),
                ),
                const Icon(Icons.crop_square, color: _kDarkText, size: 18),
              ],
            ),
            const SizedBox(width: 14),
            // Right column: labels + inputs
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'PICKUP LOCATION',
                    style: TextStyle(
                      fontSize: 10,
                      color: _kTextSecondary,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _LocationTextField(controller: pickupController),
                  const SizedBox(height: 14),
                  const Text(
                    'DESTINATION',
                    style: TextStyle(
                      fontSize: 10,
                      color: _kTextSecondary,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _LocationTextField(
                    controller: destinationController,
                    hint: 'Where to?',
                    suffix: Icons.location_on_outlined,
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

class _DashedLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const dashHeight = 4.0;
    const dashSpace = 3.0;
    final paint = Paint()
      ..color = const Color(0xFFCCCCCC)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    double startY = 0;
    while (startY < size.height) {
      canvas.drawLine(
        Offset(size.width / 2, startY),
        Offset(size.width / 2, startY + dashHeight),
        paint,
      );
      startY += dashHeight + dashSpace;
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter oldDelegate) => false;
}

class _LocationTextField extends StatelessWidget {
  const _LocationTextField({
    required this.controller,
    this.hint,
    this.suffix,
  });

  final TextEditingController controller;
  final String? hint;
  final IconData? suffix;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: const TextStyle(
        color: _kDarkText,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _kTextSecondary, fontSize: 14),
        suffixIcon: suffix != null
            ? Icon(suffix, size: 18, color: _kTextSecondary)
            : null,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        filled: true,
        fillColor: _kOffWhite,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE8E8E8)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE8E8E8)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _kGold, width: 1.5),
        ),
      ),
    );
  }
}

// ─── Recent Destinations ──────────────────────────────────────────────────────

class _RecentDestinationsSection extends StatelessWidget {
  const _RecentDestinationsSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'RECENT DESTINATIONS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: _kDarkText,
                  letterSpacing: 1.4,
                ),
              ),
              GestureDetector(
                onTap: () {
                  // TODO(MSP-XX): navigate to full recent destinations list
                },
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
                    SizedBox(width: 2),
                    Icon(Icons.arrow_forward_ios, size: 11, color: _kGold),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 64,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _kRecentDestinations.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) =>
                _RecentDestinationCard(destination: _kRecentDestinations[i]),
          ),
        ),
      ],
    );
  }
}

class _RecentDestinationCard extends StatelessWidget {
  const _RecentDestinationCard({required this.destination});

  final _RecentDestination destination;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF0D6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(destination.icon, size: 20, color: _kDarkText),
          ),
          const SizedBox(width: 10),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                destination.label,
                style: const TextStyle(
                  color: _kDarkText,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                destination.sublabel,
                style: const TextStyle(color: _kTextSecondary, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Surge Pricing Banner ─────────────────────────────────────────────────────

/// Shown when surge multiplier > 1.0 — PRD surge pricing rules apply.
/// Surge locks at booking time; does not update if surge activates after driver accept.
class _SurgePricingBanner extends StatelessWidget {
  const _SurgePricingBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _kGold,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.trending_up,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Surge Pricing Active',
                      style: TextStyle(
                        color: _kDarkText,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _kGold,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        '1.2x',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'High demand in Kumasi. Fares are slightly higher to attract more drivers.',
                  style: TextStyle(color: _kTextSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Vehicle Selection ────────────────────────────────────────────────────────

class _VehicleSelectionSection extends StatelessWidget {
  const _VehicleSelectionSection({
    required this.vehicles,
    required this.selectedId,
    required this.onSelect,
  });

  final List<_VehicleOption> vehicles;
  final String selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Select Vehicle',
                style: TextStyle(
                  color: _kDarkText,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              GestureDetector(
                onTap: () {
                  // TODO(MSP-XX): navigate to all vehicle types
                },
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
                    SizedBox(width: 2),
                    Icon(Icons.arrow_forward_ios, size: 11, color: _kGold),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: vehicles
                .map(
                  (v) => _VehicleCard(
                    vehicle: v,
                    isSelected: v.id == selectedId,
                    onTap: () => onSelect(v.id),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({
    required this.vehicle,
    required this.isSelected,
    required this.onTap,
  });

  final _VehicleOption vehicle;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFF8EC) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? _kGold : const Color(0xFFEEEEEE),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Row(
              children: [
                // Vehicle icon area
                Container(
                  width: 68,
                  height: 52,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFFFFF0CC)
                        : _kSurfaceGrey,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    vehicle.iconData,
                    size: 36,
                    color: _kDarkSlate,
                  ),
                ),
                const SizedBox(width: 12),
                // Name + description
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            vehicle.name,
                            style: const TextStyle(
                              color: _kDarkText,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.people_outlined,
                            size: 14,
                            color: _kTextSecondary,
                          ),
                          Text(
                            '${vehicle.capacity}',
                            style: const TextStyle(
                              color: _kTextSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        vehicle.description,
                        style: const TextStyle(
                          color: _kTextSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Price + ETA
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'GH₵ ${vehicle.fareGhs.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: _kDarkText,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.access_time,
                          size: 12,
                          color: _kTextSecondary,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${vehicle.etaMinutes} min',
                          style: const TextStyle(
                            color: _kTextSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            // Selected badge
            if (isSelected)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    color: _kGold,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.verified,
                    color: Colors.white,
                    size: 14,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Payment Footer ───────────────────────────────────────────────────────────

/// Sticky bottom section — payment method, confirm, and cancel.
/// Payment is initiated post-booking via POST /v1/payments/initiate (EDD §6).
class _PaymentFooter extends StatelessWidget {
  const _PaymentFooter({
    required this.onConfirm,
    required this.onCancel,
  });

  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Payment method row
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _kSurfaceGrey,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.phone_android,
                  size: 22,
                  color: _kDarkSlate,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'PAYMENT',
                      style: TextStyle(
                        fontSize: 10,
                        color: _kTextSecondary,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.6,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'MTN Mobile Money',
                      style: TextStyle(
                        color: _kDarkText,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () {
                  // TODO(MSP-XX): navigate to payment method selection
                },
                child: const Text(
                  'Change',
                  style: TextStyle(
                    color: _kGold,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Confirm Ride CTA
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: onConfirm,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kDarkSlate,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'Confirm Ride',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Cancel + free cancellation note
          GestureDetector(
            onTap: onCancel,
            child: const Text(
              'Cancel Request',
              style: TextStyle(
                color: _kDarkText,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Free cancellation within 3 minutes of match.',
            style: TextStyle(color: _kTextSecondary, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
