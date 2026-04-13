import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// ─── Design Tokens ─────────────────────────────────────────────────────────────
// Source: CLAUDE.md §5.2
const _kGold = Color(0xFFF5A623);
const _kDarkSlate = Color(0xFF46535D);
const _kDarkText = Color(0xFF161A1D);
const _kTextSecondary = Color(0xFF555E68);
const _kSurfaceGrey = Color(0xFFF3F5F6);
const _kError = Color(0xFFEB5757);
const _kSuccess = Color(0xFF27AE60);

// ─── Screen ───────────────────────────────────────────────────────────────────

/// Active ride tracking — live driver position and ETA on map.
///
/// PRD §4.6 | EDD §4:
/// - Live updates: WebSocket ws://api/v1/rides/:id/live
/// - In-app chat: WebSocket ws://api/v1/chat/:bookingId
/// - Share trip: GET /v1/rides/:id/share
/// - SOS: two-step confirm → dial 191 + trigger recording (CLAUDE.md §8.3)
/// - Phone calls masked — neither party sees real number (CLAUDE.md §8.4)
class RideTrackingScreen extends ConsumerStatefulWidget {
  const RideTrackingScreen({super.key});

  @override
  ConsumerState<RideTrackingScreen> createState() => _RideTrackingScreenState();
}

class _RideTrackingScreenState extends ConsumerState<RideTrackingScreen> {
  GoogleMapController? _mapController;

  // Kumasi Central Market — pilot city (PRD §1.1)
  static const _kInitialCamera = CameraPosition(
    target: LatLng(6.6885, -1.6244),
    zoom: 15.5,
    tilt: 25,
  );

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final topInset = MediaQuery.of(context).padding.top;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFFE8ECF0),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Google Map — driver position updated via WebSocket ──────────────
          GoogleMap(
            initialCameraPosition: _kInitialCamera,
            onMapCreated: (c) => _mapController = c,
            myLocationEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: false,
          ),

          // ── Route line (Polyline added to GoogleMap in Phase 2) ─────────────
          CustomPaint(painter: _RoutePainter()),

          // ── Driver location pin ─────────────────────────────────────────────
          Positioned(
            left: screenSize.width * 0.26 - 23,
            top: screenSize.height * 0.34 - 28,
            child: const _MapLocationPin(),
          ),

          // ── Back button + ETA pill ──────────────────────────────────────────
          Positioned(
            top: topInset + 12,
            left: 16,
            right: 16,
            child: const _TopControlsRow(),
          ),

          // ── Destination floating card ───────────────────────────────────────
          Positioned(
            top: topInset + 68,
            left: 16,
            right: 16,
            child: const _DestinationCard(),
          ),

          // ── Driver info bottom sheet ────────────────────────────────────────
          Align(
            alignment: Alignment.bottomCenter,
            child: _DriverBottomSheet(bottomInset: bottomInset),
          ),

          // ── SOS emergency button (CLAUDE.md §8.3) ──────────────────────────
          Positioned(
            bottom: bottomInset + 108,
            right: 16,
            child: const _SosButton(),
          ),
        ],
      ),
    );
  }
}

// ─── Map Overlays ─────────────────────────────────────────────────────────────

class _RoutePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF2D3E4A)
      ..strokeWidth = 5.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(size.width * 0.28, size.height * 0.34)
      ..quadraticBezierTo(
        size.width * 0.31,
        size.height * 0.46,
        size.width * 0.46,
        size.height * 0.54,
      );

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_RoutePainter old) => false;
}

class _MapLocationPin extends StatelessWidget {
  const _MapLocationPin();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: const BoxDecoration(
            color: _kDarkSlate,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.location_on, color: Colors.white, size: 24),
        ),
        Container(width: 3, height: 10, color: _kDarkSlate),
      ],
    );
  }
}

// ─── Top Controls ─────────────────────────────────────────────────────────────

class _TopControlsRow extends StatelessWidget {
  const _TopControlsRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Back button
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: const [
                BoxShadow(
                  color: Color(0x16000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(Icons.arrow_back, color: _kDarkText, size: 20),
          ),
        ),
        const SizedBox(width: 12),
        // ETA pill
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x16000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: const Text(
              'ARRIVING IN 4 MINS',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _kTextSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Destination Card ─────────────────────────────────────────────────────────

class _DestinationCard extends StatelessWidget {
  const _DestinationCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x16000000),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left: icons + connector line
            Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: _kGold,
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 1,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: const Color(0xFFDDDDDD),
                  ),
                ),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: _kGold, width: 2),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            // Right: text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'HEADING TO',
                    style: TextStyle(
                      fontSize: 10,
                      color: _kTextSecondary,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Kumasi City Mall, Lake Road',
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
    );
  }
}

// ─── Driver Bottom Sheet ──────────────────────────────────────────────────────

class _DriverBottomSheet extends StatelessWidget {
  const _DriverBottomSheet({required this.bottomInset});

  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Color(0x16000000),
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFDDDDDD),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          // Fare + payment type badge
          const _FareBadgeRow(),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Divider(height: 1, thickness: 1, color: Color(0xFFF0F0F0)),
          ),
          // Driver info
          const _DriverInfoRow(),
          const SizedBox(height: 16),
          // Chat + Phone
          const _ChatPhoneRow(),
          const SizedBox(height: 12),
          // Share Trip + Send ETA
          const _SecondaryActionsRow(),
          const SizedBox(height: 14),
          // Safety note
          const _SafetyNote(),
        ],
      ),
    );
  }
}

// ─── Fare Badge Row ───────────────────────────────────────────────────────────

class _FareBadgeRow extends StatelessWidget {
  const _FareBadgeRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'GH₵ 42.50',
          style: TextStyle(
            color: _kDarkText,
            fontSize: 26,
            fontWeight: FontWeight.bold,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _kGold.withAlpha(20),
            border: Border.all(color: _kGold),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Text(
            'CASH TRIP',
            style: TextStyle(
              color: _kGold,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Driver Info Row ──────────────────────────────────────────────────────────

class _DriverInfoRow extends StatelessWidget {
  const _DriverInfoRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Avatar with online dot
        Stack(
          clipBehavior: Clip.none,
          children: [
            ClipOval(
              child: Image.network(
                'https://i.pravatar.cc/150?img=52',
                width: 54,
                height: 54,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 54,
                  height: 54,
                  color: _kSurfaceGrey,
                  child: const Icon(Icons.person, size: 30, color: _kDarkSlate),
                ),
              ),
            ),
            Positioned(
              bottom: 1,
              right: 1,
              child: Container(
                width: 14,
                height: 14,
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
        // Name + rating + verified badge
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Kofi Mensah',
                style: TextStyle(
                  color: _kDarkText,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 5),
              Row(
                children: [
                  const Icon(
                    Icons.star_border_rounded,
                    size: 15,
                    color: _kGold,
                  ),
                  const SizedBox(width: 3),
                  const Text(
                    '4.9',
                    style: TextStyle(
                      color: _kGold,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Text(
                    ' • ',
                    style: TextStyle(color: _kTextSecondary, fontSize: 13),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFDDDDDD)),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.verified_outlined,
                          size: 11,
                          color: _kDarkSlate,
                        ),
                        SizedBox(width: 3),
                        Text(
                          'Verified',
                          style: TextStyle(
                            color: _kDarkSlate,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Car info (right-aligned)
        const Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'Toyota Vitz',
              style: TextStyle(color: _kTextSecondary, fontSize: 12),
            ),
            SizedBox(height: 3),
            Text(
              'GW 492 - 22',
              style: TextStyle(
                color: _kDarkText,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Chat + Phone Row ─────────────────────────────────────────────────────────

class _ChatPhoneRow extends StatelessWidget {
  const _ChatPhoneRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Chat CTA — WebSocket ws://api/v1/chat/:bookingId
        Expanded(
          child: SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: () {
                // TODO(MSP-XX): open in-app chat (WebSocket ws://api/v1/chat/:bookingId)
              },
              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 20),
              label: const Text(
                'Chat with Kofi',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kDarkSlate,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Masked phone call (CLAUDE.md §8.4 — neither party sees real number)
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFDDDDDD), width: 1.5),
            borderRadius: BorderRadius.circular(14),
          ),
          child: IconButton(
            onPressed: () {
              // TODO(MSP-XX): masked call — routed via backend infrastructure
            },
            icon: const Icon(Icons.call_outlined, size: 22, color: _kDarkText),
          ),
        ),
      ],
    );
  }
}

// ─── Secondary Actions Row ────────────────────────────────────────────────────

class _SecondaryActionsRow extends StatelessWidget {
  const _SecondaryActionsRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _OutlineButton(
            icon: Icons.share_outlined,
            label: 'Share Trip',
            onTap: () {
              // TODO(MSP-XX): GET /v1/rides/:id/share — link expires 30 min post-completion
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _OutlineButton(
            icon: Icons.access_time_outlined,
            label: 'Send ETA',
            onTap: () {
              // TODO(MSP-XX): share ETA with emergency contacts
            },
          ),
        ),
      ],
    );
  }
}

class _OutlineButton extends StatelessWidget {
  const _OutlineButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE0E0E0), width: 1.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: _kDarkText),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: _kDarkText,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Safety Note ──────────────────────────────────────────────────────────────

class _SafetyNote extends StatelessWidget {
  const _SafetyNote();

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(Icons.security_outlined, size: 18, color: _kDarkSlate),
        ),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'Your safety is our priority. In-app recording is active for this trip. Share your live location with family for extra peace of mind.',
            style: TextStyle(
              color: _kTextSecondary,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── SOS Button ───────────────────────────────────────────────────────────────

/// Two-step SOS — tap triggers confirmation screen before dialling 191.
/// On confirm: GPS + emergency contacts notified, audio/video recording begins.
/// Recordings stored encrypted for 90 days (CLAUDE.md §8.3).
class _SosButton extends StatelessWidget {
  const _SosButton();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // TODO(MSP-XX): show two-step SOS confirmation, then dial 191
        showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Emergency SOS'),
            content: const Text(
              'This will alert emergency contacts, start recording, and dial Ghana Police (191). Continue?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Call 191',
                  style: TextStyle(color: _kError),
                ),
              ),
            ],
          ),
        );
      },
      child: Container(
        width: 62,
        height: 62,
        decoration: BoxDecoration(
          color: _kError,
          shape: BoxShape.circle,
          boxShadow: const [
            BoxShadow(
              color: Color(0x44EB5757),
              blurRadius: 14,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.security, color: Colors.white, size: 22),
            SizedBox(height: 2),
            Text(
              'SOS',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
