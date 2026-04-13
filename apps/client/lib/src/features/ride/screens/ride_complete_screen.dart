import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─── Design Tokens ─────────────────────────────────────────────────────────────
// Source: CLAUDE.md §5.2
const _kGold = Color(0xFFF5A623);
const _kDarkSlate = Color(0xFF46535D);
const _kDarkText = Color(0xFF161A1D);
const _kTextSecondary = Color(0xFF555E68);
const _kSurfaceGrey = Color(0xFFF3F5F6);
const _kOffWhite = Color(0xFFF6F7F8);
const _kSuccess = Color(0xFF27AE60);

// ─── Screen ───────────────────────────────────────────────────────────────────

/// Ride complete screen — fare summary, tip submission, and payment receipt.
/// PRD §4.3 | EDD §4: final fare from GPS trail, tip via POST /v1/payments/:id/tip
/// Zero commission on tips; full amount goes directly to driver.
class RideCompleteScreen extends ConsumerStatefulWidget {
  const RideCompleteScreen({super.key});

  @override
  ConsumerState<RideCompleteScreen> createState() => _RideCompleteScreenState();
}

class _RideCompleteScreenState extends ConsumerState<RideCompleteScreen> {
  int? _selectedTipPreset; // null = no preset selected
  final _customTipController = TextEditingController();
  int _navIndex = 0;

  @override
  void dispose() {
    _customTipController.dispose();
    super.dispose();
  }

  bool get _tipConfirmEnabled =>
      _selectedTipPreset != null || _customTipController.text.trim().isNotEmpty;

  void _onPresetTap(int amount) {
    setState(() {
      _selectedTipPreset = _selectedTipPreset == amount ? null : amount;
      if (_selectedTipPreset != null) _customTipController.clear();
    });
  }

  void _onCustomChanged(String _) {
    setState(() => _selectedTipPreset = null);
  }

  void _onConfirmTip() {
    // TODO(MSP-XX): POST /v1/payments/:id/tip — zero commission, full to driver
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kOffWhite,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        leading: const BackButton(color: _kDarkText),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: const [
            Text(
              'Arrived Safe',
              style: TextStyle(
                color: _kDarkText,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'Thursday, 24 Oct • 14:32',
              style: TextStyle(color: _kTextSecondary, fontSize: 12),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: Colors.grey[200]!),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            const _DriverTripCard(),
            const SizedBox(height: 12),
            const _FareBreakdownCard(),
            const SizedBox(height: 12),
            _TipSection(
              selectedTipPreset: _selectedTipPreset,
              customTipController: _customTipController,
              confirmEnabled: _tipConfirmEnabled,
              onPresetTap: _onPresetTap,
              onCustomChanged: _onCustomChanged,
              onConfirm: _onConfirmTip,
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _navIndex,
        onTap: (i) => setState(() => _navIndex = i),
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
            icon: Icon(Icons.access_time_outlined),
            activeIcon: Icon(Icons.access_time),
            label: 'Activity',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet_outlined),
            activeIcon: Icon(Icons.account_balance_wallet),
            label: 'Wallet',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Account',
          ),
        ],
      ),
    );
  }
}

// ─── Driver + Trip Card ───────────────────────────────────────────────────────

class _DriverTripCard extends StatelessWidget {
  const _DriverTripCard();

  @override
  Widget build(BuildContext context) {
    return Container(
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
      child: Column(
        children: [
          // Driver info row
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Avatar with online dot
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipOval(
                      child: Image.network(
                        'https://i.pravatar.cc/150?img=52',
                        width: 50,
                        height: 50,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 50,
                          height: 50,
                          color: _kSurfaceGrey,
                          child: const Icon(
                            Icons.person,
                            size: 28,
                            color: _kDarkSlate,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 1,
                      right: 1,
                      child: Container(
                        width: 13,
                        height: 13,
                        decoration: BoxDecoration(
                          color: _kSuccess,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                // Name + car + verified badge
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Kwesi Mensah',
                        style: TextStyle(
                          color: _kDarkText,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'Toyota Vitz • GW-482-22',
                        style: TextStyle(color: _kTextSecondary, fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: _kGold.withAlpha(80)),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.verified_outlined, size: 12, color: _kGold),
                            SizedBox(width: 4),
                            Text(
                              'Verified',
                              style: TextStyle(
                                color: _kGold,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Rating
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star_border_rounded, size: 16, color: _kGold),
                    SizedBox(width: 3),
                    Text(
                      '4.9',
                      style: TextStyle(
                        color: _kDarkText,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const Divider(height: 1, thickness: 1, color: Color(0xFFF0F0F0)),

          // Pickup → Destination route
          Padding(
            padding: const EdgeInsets.all(14),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Left: icons + dashed connector
                  Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Icon(
                        Icons.trip_origin,
                        size: 18,
                        color: _kDarkSlate,
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: CustomPaint(
                            painter: _VerticalDashPainter(),
                            child: const SizedBox(width: 2),
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.circle_outlined,
                        size: 18,
                        color: _kGold,
                      ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  // Right: labels + locations
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'PICKUP',
                          style: TextStyle(
                            fontSize: 10,
                            color: _kTextSecondary,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Makola Market, Accra Central',
                          style: TextStyle(
                            color: _kDarkText,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(height: 16),
                        Text(
                          'DESTINATION',
                          style: TextStyle(
                            fontSize: 10,
                            color: _kTextSecondary,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Kotoka International Airport (T3)',
                          style: TextStyle(
                            color: _kDarkText,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
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

// ─── Fare Breakdown Card ──────────────────────────────────────────────────────

/// Final fare calculated from actual GPS trail + duration (EDD §4).
/// Components: base + distance (per km) + time (per min) + surge multiplier.
class _FareBreakdownCard extends StatelessWidget {
  const _FareBreakdownCard();

  @override
  Widget build(BuildContext context) {
    return Container(
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text(
                  'Fare Breakdown',
                  style: TextStyle(
                    color: _kDarkText,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'ID: #RID-92834',
                  style: TextStyle(
                    color: _kGold,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFFF0F0F0)),

          // Fare rows
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: Column(
              children: [
                const _FareRow(label: 'Base Fare', value: 'GHS 12.00'),
                const SizedBox(height: 10),
                const _FareRow(
                  label: 'Distance (8.4 km)',
                  value: 'GHS 32.50',
                ),
                const SizedBox(height: 10),
                const _FareRow(label: 'Time (24 mins)', value: 'GHS 6.00'),
                const SizedBox(height: 10),
                // Surge row with lightning icon
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bolt, size: 14, color: _kTextSecondary),
                        SizedBox(width: 4),
                        Text(
                          'Surge Pricing (1.2x)',
                          style: TextStyle(
                            color: _kTextSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'GHS 9.20',
                      style: TextStyle(color: _kTextSecondary, fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Dashed separator before subtotals
                const _HorizontalDashDivider(),
                const SizedBox(height: 14),
                const _FareRow(label: 'Subtotal', value: 'GHS 59.70'),
                const SizedBox(height: 10),
                const _FareRow(
                  label: 'Taxes & Levies',
                  value: 'GHS 1.80',
                ),
                const SizedBox(height: 10),
                const _FareRow(
                  label: 'Promotional Discount',
                  value: '- GHS 5.00',
                ),
                const SizedBox(height: 14),
                const Divider(
                  height: 1,
                  thickness: 1,
                  color: Color(0xFFF0F0F0),
                ),
                const SizedBox(height: 14),
                const _FareRow(
                  label: 'Total Paid',
                  value: 'GHS 56.50',
                  bold: true,
                ),
                const SizedBox(height: 14),
              ],
            ),
          ),

          // Payment method row
          const Divider(height: 1, thickness: 1, color: Color(0xFFF0F0F0)),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _kSurfaceGrey,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.credit_card_outlined,
                    size: 20,
                    color: _kDarkSlate,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'MTN Mobile Money',
                    style: TextStyle(
                      color: _kDarkText,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const Text(
                  'SUCCESS',
                  style: TextStyle(
                    color: _kTextSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FareRow extends StatelessWidget {
  const _FareRow({
    required this.label,
    required this.value,
    this.bold = false,
  });

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: bold ? _kDarkText : _kTextSecondary,
            fontSize: bold ? 14 : 13,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: _kDarkText,
            fontSize: bold ? 16 : 13,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}

// ─── Tip Section ──────────────────────────────────────────────────────────────

/// Tip is submitted separately via POST /v1/payments/:id/tip (EDD §6).
/// 0% platform commission — full tip amount goes to driver.
class _TipSection extends StatelessWidget {
  const _TipSection({
    required this.selectedTipPreset,
    required this.customTipController,
    required this.confirmEnabled,
    required this.onPresetTap,
    required this.onCustomChanged,
    required this.onConfirm,
  });

  final int? selectedTipPreset;
  final TextEditingController customTipController;
  final bool confirmEnabled;
  final ValueChanged<int> onPresetTap;
  final ValueChanged<String> onCustomChanged;
  final VoidCallback onConfirm;

  static const _kPresets = [2, 5, 10];

  @override
  Widget build(BuildContext context) {
    return Container(
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Add tip?',
            style: TextStyle(
              color: _kDarkText,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 14),
          // Preset tip chips
          Row(
            children: _kPresets.asMap().entries.map((entry) {
              final i = entry.key;
              final amount = entry.value;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i < _kPresets.length - 1 ? 8 : 0),
                  child: _TipPresetChip(
                    label: 'GHS $amount',
                    isSelected: selectedTipPreset == amount,
                    onTap: () => onPresetTap(amount),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          // Custom amount field
          TextField(
            controller: customTipController,
            onChanged: onCustomChanged,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: _kDarkText, fontSize: 14),
            decoration: InputDecoration(
              prefixText: 'GHS   ',
              prefixStyle: const TextStyle(
                color: _kTextSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              hintText: 'Other amount',
              hintStyle: const TextStyle(color: _kTextSecondary, fontSize: 14),
              filled: true,
              fillColor: _kOffWhite,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 13,
              ),
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
          ),
          const SizedBox(height: 10),
          // Zero-commission note
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(Icons.info_outline, size: 14, color: _kGold),
              ),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  '100% of tips go directly to Kwasi. Zero commission charged.',
                  style: TextStyle(color: _kGold, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Confirm tip button — active only when a tip is selected/entered
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: confirmEnabled ? onConfirm : null,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    confirmEnabled ? _kDarkSlate : const Color(0xFFE0E0E0),
                foregroundColor:
                    confirmEnabled ? Colors.white : _kTextSecondary,
                disabledBackgroundColor: const Color(0xFFE0E0E0),
                disabledForegroundColor: _kTextSecondary,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'CONFIRM TIP',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TipPresetChip extends StatelessWidget {
  const _TipPresetChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: isSelected ? _kGold.withAlpha(30) : _kSurfaceGrey,
          borderRadius: BorderRadius.circular(8),
          border: isSelected
              ? Border.all(color: _kGold, width: 1.5)
              : null,
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? _kGold : _kDarkText,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Painters ─────────────────────────────────────────────────────────────────

class _VerticalDashPainter extends CustomPainter {
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
  bool shouldRepaint(_VerticalDashPainter old) => false;
}

class _HorizontalDashDivider extends StatelessWidget {
  const _HorizontalDashDivider();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1.5,
      width: double.infinity,
      child: CustomPaint(painter: _HorizontalDashPainter()),
    );
  }
}

class _HorizontalDashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const dashWidth = 6.0;
    const dashSpace = 4.0;
    final paint = Paint()
      ..color = const Color(0xFFDDDDDD)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    double startX = 0;
    while (startX < size.width) {
      canvas.drawLine(
        Offset(startX, 0),
        Offset(startX + dashWidth, 0),
        paint,
      );
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(_HorizontalDashPainter old) => false;
}
