# Flutter Design System Plugin
## MyShop Mobile — `myshop_ui` Package Reference

> **Read this plugin before building any screen or widget.** All UI must use these tokens — never hardcode colors, font sizes, or spacing values.

---

## 1. Color System

All colors are defined in `packages/myshop_ui/lib/src/theme/myshop_colors.dart`:

```dart
import 'package:flutter/material.dart';

abstract final class MyShopColors {
  // ── Primary (from Figma) ──
  static const primaryGold = Color(0xFFF5A623);        // Primary accent — CTAs, active tabs, tags, highlights
  static const primaryGoldDark = Color(0xFFD48E1A);    // Pressed state
  static const primaryGoldLight = Color(0xFFFFF8EC);   // Tinted backgrounds
  static const darkSlate = Color(0xFF46535D);           // Dark accent — icon backgrounds (rides), inactive nav
  static const darkText = Color(0xFF161A1D);            // Primary text, headings
  static const offWhite = Color(0xFFF6F7F8);            // Sheet/card background

  // ── Semantic ──
  static const success = Color(0xFF27AE60);
  static const successLight = Color(0xFFE8F8EF);
  static const warning = Color(0xFFF2994A);
  static const warningLight = Color(0xFFFEF3E8);
  static const error = Color(0xFFEB5757);
  static const errorLight = Color(0xFFFDE8E8);
  static const info = Color(0xFF2F80ED);
  static const infoLight = Color(0xFFE8F0FD);

  // ── Surface ──
  static const surfaceWhite = Color(0xFFFFFFFF);
  static const surfaceGrey = Color(0xFFF3F5F6);        // Subtle backgrounds (drag handle, icon circles)
  static const divider = Color(0xFFE0E0E0);
  static const disabled = Color(0xFFBDBDBD);
  static const shimmerBase = Color(0xFFE0E0E0);
  static const shimmerHighlight = Color(0xFFF5F5F5);
  static const avatarPlaceholder = Color(0xFFE0E6FF);   // Default avatar background

  // ── Text ──
  static const textPrimary = Color(0xFF161A1D);         // Headings, titles, body
  static const textSecondary = Color(0xFF555E68);        // Descriptions, captions, timestamps
  static const textHint = Color(0xFFBDBDBD);
  static const textOnPrimary = Color(0xFFFFFFFF);        // Text on primaryGold buttons
  static const textOnDarkSlate = Color(0xFFFFFFFF);      // Text/icons on darkSlate backgrounds

  // ── Status-specific (Provider) ──
  static const online = Color(0xFF27AE60);
  static const offline = Color(0xFFBDBDBD);
  static const busy = Color(0xFFF2994A);
  static const surge = Color(0xFFEB5757);

  // ── Rating ──
  static const ratingStar = Color(0xFFF5A623);           // primaryGold
  static const ratingStarEmpty = Color(0xFFE0E0E0);
}
```

### Semantic Color Usage

| Context | Color | Usage |
|---------|-------|-------|
| Primary CTA / Active tab / Tags / Highlights | `primaryGold` | Buttons, active nav, promo tags, current location text |
| Ride icon background / Dark accents | `darkSlate` | Icon containers, inactive nav items |
| Completed / Verified / Online | `success` | Status badge, checkmark |
| Pending / En route / Surge | `warning` | Status badge, surge indicator |
| Cancelled / Emergency / Error | `error` | Status badge, error messages |
| Rating stars (filled) | `ratingStar` | Star icons (same as primaryGold) |
| Commission / Earnings highlight | `primaryGold` | Earnings amount |
| Disabled / Offline | `disabled` | Toggle, button |

---

## 2. Typography System

Defined in `packages/myshop_ui/lib/src/theme/myshop_typography.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'myshop_colors.dart';

abstract final class MyShopTypography {
  static final _baseFont = GoogleFonts.raleway;
  static final _navFont = GoogleFonts.raleway;   // Bottom nav labels only

  // ── Display ──
  static final display = _baseFont(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: MyShopColors.textPrimary,
    height: 1.3,
  );

  // ── Headings ──
  static final h1 = _baseFont(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: MyShopColors.textPrimary,
    height: 1.3,
  );

  static final h2 = _baseFont(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: MyShopColors.textPrimary,
    height: 1.35,
  );

  static final h3 = _baseFont(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: MyShopColors.textPrimary,
    height: 1.28,
  );

  // ── Body ──
  static final body1 = _baseFont(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: MyShopColors.textPrimary,
    height: 1.43,
  );

  static final body2 = _baseFont(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: MyShopColors.textSecondary,
    height: 1.42,
  );

  // ── Supporting ──
  static final caption = _baseFont(
    fontSize: 10,
    fontWeight: FontWeight.w400,
    color: MyShopColors.textSecondary,
    height: 1.6,
  );

  static final button = _baseFont(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: MyShopColors.textOnPrimary,
    height: 1.57,
  );

  static final overline = _baseFont(
    fontSize: 10,
    fontWeight: FontWeight.w900,
    color: MyShopColors.textSecondary,
    letterSpacing: 1.4,
    height: 1.4,
  );

  // ── Navigation ──
  static final navLabel = _navFont(
    fontSize: 10,
    fontWeight: FontWeight.w700,
    color: MyShopColors.primaryGold,   // Active tab
    height: 1.6,
  );

  static final navLabelInactive = _navFont(
    fontSize: 10,
    fontWeight: FontWeight.w400,
    color: MyShopColors.darkSlate,     // Inactive tab
    height: 1.6,
  );

  // ── Special ──
  static final price = _baseFont(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: MyShopColors.textPrimary,
    height: 1.2,
  );

  static final priceSmall = _baseFont(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: MyShopColors.textPrimary,
    height: 1.2,
  );
}
```

---

## 3. Spacing Scale

Defined in `packages/myshop_ui/lib/src/theme/myshop_spacing.dart`:

```dart
abstract final class MyShopSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  // Common paddings
  static const screenHorizontal = EdgeInsets.symmetric(horizontal: xl);   // 32
  static const screenAll = EdgeInsets.all(md);                            // 16
  static const cardContent = EdgeInsets.all(md);                          // 16
  static const sectionGap = SizedBox(height: lg);                        // 24
  static const itemGap = SizedBox(height: sm);                           // 8
  static const tightGap = SizedBox(height: xs);                          // 4
}
```

---

## 4. Component Patterns

### 4.1 Primary Button

```dart
class MyShopButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isFullWidth;
  final ButtonVariant variant;

  // variant: primary (blue), secondary (outlined), danger (red), gold (yellow)

  // Primary: filled primaryGold, white text, 8dp radius, 52dp height, full-width
  // Secondary: outlined primaryGold border, gold text, transparent fill
  // Disabled: surfaceGrey fill, disabled text color
  // Loading: show CircularProgressIndicator in button, disable tap
}
```

### 4.2 Input Field

```dart
class MyShopInput extends StatelessWidget {
  // OutlinedInputBorder with 8dp radius
  // 48dp height minimum
  // Label above field (not floating)
  // Error text below field in error color
  // Suffix icon for password toggle, search, clear
  // Prefix icon for phone, email, location
  // Ghana phone input: +233 prefix chip + 9-digit field
}
```

### 4.3 Cards

```dart
class MyShopCard extends StatelessWidget {
  // 12dp borderRadius
  // surfaceWhite background
  // Elevation 2 (subtle shadow)
  // cardContent padding (16dp all)
  // Optional onTap with InkWell
}
```

### 4.4 Status Badge

```dart
class StatusBadge extends StatelessWidget {
  // Pill shape (full radius)
  // Background: semantic color light variant
  // Text: semantic color (dark)
  // Overline typography
  // Dot indicator before text (optional)
  // Used for: RideStatus, JobStatus, VerificationStatus, PaymentStatus
}
```

### 4.5 Rating Stars

```dart
class RatingStars extends StatelessWidget {
  // 5 stars, primaryGold filled, surfaceGrey empty
  // Support half-stars for display
  // Interactive mode for submission (tap to rate)
  // Show numeric value beside stars: "4.5 (123 reviews)"
}
```

### 4.6 Floating Mini-Card (Active Booking)

```dart
class ActiveBookingMiniCard extends StatelessWidget {
  // 60dp height, sticks above BottomNavigationBar
  // Rounded top corners (12dp)
  // Shows: status icon + provider name + status text + chevron
  // Ride card: darkSlate left accent
  // Artisan job card: primaryGold left accent
  // Tappable — expands to full tracking screen
  // Both can be visible simultaneously (stacked)
}
```

### 4.7 Loading Skeleton

```dart
class SkeletonLoader extends StatelessWidget {
  // Shimmer animation using shimmerBase → shimmerHighlight
  // Match the shape of the content it replaces
  // Variants: SkeletonLine, SkeletonCircle, SkeletonCard
  // NEVER use CircularProgressIndicator / spinner for page loads
  // Spinners are acceptable only for inline button loading states
}
```

### 4.8 Empty State

```dart
class EmptyStateWidget extends StatelessWidget {
  // Centered illustration (SVG or Lottie)
  // h2 title: "No rides yet"
  // body2 description: "Book your first ride to get started"
  // Primary CTA button below
  // Used when lists are empty, search returns no results, etc.
}
```

### 4.9 Error State

```dart
class ErrorStateWidget extends StatelessWidget {
  // Centered error illustration
  // h3 title: "Something went wrong"
  // body2 description with specific error context
  // "Try Again" button (secondary style)
  // NEVER show raw error messages or stack traces to users
}
```

---

## 5. Bottom Navigation

### Client App (4 tabs)

| Tab | Icon | Label | Screen |
|-----|------|-------|--------|
| Home | map pin | Home | Map-first ride booking |
| Services | grid/tools | Services | Artisan category grid |
| Activity | clock/list | Activity | Ride + job history |
| Profile | person | Profile | Settings, payment methods, saved locations |

### Provider App — Driver (4 tabs)

| Tab | Icon | Label | Screen |
|-----|------|-------|--------|
| Home | steering wheel | Home | Online toggle + ride requests |
| Earnings | wallet | Earnings | Analytics dashboard |
| Activity | clock/list | Activity | Ride history |
| Profile | person | Profile | Settings, vehicle info, documents |

### Provider App — Artisan (4 tabs)

| Tab | Icon | Label | Screen |
|-----|------|-------|--------|
| Home | briefcase | Home | Online toggle + job requests |
| Earnings | wallet | Earnings | Analytics dashboard |
| Activity | clock/list | Activity | Job history |
| Profile | person | Profile | Settings, portfolio, documents |

---

## 6. Animation Guidelines

- **Duration:** 200ms for micro-interactions (button press, toggle), 300ms for screen transitions, 500ms for skeleton shimmer cycle
- **Easing:** `Curves.easeInOut` for most transitions, `Curves.easeOut` for elements entering, `Curves.easeIn` for elements leaving
- **What to animate:** Page transitions, bottom sheet reveals, card expansions, status changes, skeleton shimmer, fab appearance
- **What NOT to animate:** Text changes, color changes on status updates (instant swap is clearer), map marker movements (Google/Mapbox handle this)

---

## 7. Ghana-Specific Formatting

```dart
// Currency: always show ₵ symbol, no decimals for whole amounts
// ₵47   (not GHS 47.00, not GH₵ 47)
// ₵1,250 (comma separator for thousands)

// Phone: +233 XX XXX XXXX
// Display: +233 24 123 4567
// Input: show +233 prefix chip, user enters 9 digits

// Date/Time: dd MMM yyyy, HH:mm (24-hour)
// 15 Mar 2026, 14:30

// Distance: km with 1 decimal
// 3.2 km

// Duration: Xh Ym or Xm
// 1h 30m, 45m, 2h
```
