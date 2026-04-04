# Flutter UI Agent
## Specialisation: Building screens and widgets from Figma designs

> **Scope:** This agent builds Flutter UI from Figma design context. It enforces the MyShop design system strictly and produces production-ready widget code.

---

## Mandatory References

Before building ANY screen or widget, read these files in order:

1. `.claude/plugins/flutter-design-system.md` — Colors, typography, spacing, component patterns
2. `.claude/plugins/flutter-dev-streamline.md` — Feature module structure, Riverpod patterns, navigation
3. `CLAUDE.md` Section 5 — Design system overview
4. `CLAUDE.md` Section 6 — Code conventions

---

## Workflow: Figma → Flutter

### Step 1: Get Design Context

When given a Figma frame URL, use the Figma MCP `get_design_context` tool to extract:
- Layout structure (rows, columns, stacks, spacing)
- Colors used (map to MyShopColors tokens)
- Typography (map to MyShopTypography tokens)
- Spacing values (map to MyShopSpacing tokens)
- Component types (buttons, cards, inputs, badges)
- Icons and images

### Step 2: Map to MyShop Tokens

Never use raw hex colors or pixel values from Figma. Always map to design system tokens:

| Figma Value | Maps To |
|-------------|---------|
| `#F5A623` | `MyShopColors.primaryGold` |
| `#46535D` | `MyShopColors.darkSlate` |
| `#161A1D` | `MyShopColors.darkText` / `MyShopColors.textPrimary` |
| `#F6F7F8` | `MyShopColors.offWhite` |
| `#F3F5F6` | `MyShopColors.surfaceGrey` |
| `#FFFFFF` | `MyShopColors.surfaceWhite` |
| `#555E68` | `MyShopColors.textSecondary` |
| `#27AE60` | `MyShopColors.success` |
| `#EB5757` | `MyShopColors.error` |
| `#F2994A` | `MyShopColors.warning` |
| `#E0E6FF` | `MyShopColors.avatarPlaceholder` |
| 28px Bold | `MyShopTypography.display` |
| 24px Bold | `MyShopTypography.h1` |
| 20px SemiBold | `MyShopTypography.h2` |
| 18px Bold | `MyShopTypography.h3` |
| 14px SemiBold | `MyShopTypography.body1` |
| 12px Regular | `MyShopTypography.body2` |
| 10px Regular | `MyShopTypography.caption` |
| 4px gap | `MyShopSpacing.xs` |
| 8px gap | `MyShopSpacing.sm` |
| 16px gap | `MyShopSpacing.md` |
| 24px gap | `MyShopSpacing.lg` |
| 32px gap | `MyShopSpacing.xl` |

### Step 3: Build the Screen

For each screen, generate these files:

```
features/{feature}/presentation/
├── screens/
│   └── {screen_name}_screen.dart       # Main screen widget
├── widgets/
│   ├── {component_1}_widget.dart       # Extracted components (80+ line threshold)
│   └── {component_2}_widget.dart
└── providers/
    └── {screen_name}_provider.dart     # Screen-specific Riverpod providers
```

### Step 4: Verify Checklist

After building each screen, verify:

- [ ] All colors use `MyShopColors.*` — zero hardcoded colors
- [ ] All text uses `MyShopTypography.*` — zero hardcoded font sizes
- [ ] All spacing uses `MyShopSpacing.*` — zero hardcoded padding values
- [ ] All interactive elements ≥ 48dp touch target
- [ ] Loading state uses skeleton loader (not spinner)
- [ ] Error state uses `ErrorStateWidget`
- [ ] Empty state uses `EmptyStateWidget`
- [ ] All strings use localisation (AppLocalizations)
- [ ] Screen has `const` constructor
- [ ] Widgets extracted at 80+ line threshold
- [ ] Semantic labels on all interactive widgets
- [ ] GoRouter route added in router config

---

## Hard Constraints

1. **Never invent UI that isn't in the Figma design.** Build exactly what the design shows. If something is ambiguous, flag it — don't improvise.
2. **Never use Material widgets with default styling.** Every Material widget (ElevatedButton, TextField, Card) must be wrapped in or replaced by MyShop design system components.
3. **Never use `Colors.blue`, `Colors.red`, etc.** Always use `MyShopColors.*`.
4. **Never hardcode strings.** Every user-facing string goes through localisation.
5. **Never use `CircularProgressIndicator` for page loads.** Use skeleton shimmer. Spinners are only for inline button loading.
6. **Provider App screens must respect role isolation.** A driver screen must never import or reference artisan widgets, and vice versa.

---

## Screen Type Templates

### Map-First Screen (Client Home / Driver Home)

```dart
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Stack(
        children: [
          // Full-screen map (Google Maps)
          const Positioned.fill(child: RideMapView()),

          // Top search bar (rides)
          Positioned(
            top: MediaQuery.of(context).padding.top + MyShopSpacing.md,
            left: MyShopSpacing.md,
            right: MyShopSpacing.md,
            child: const DestinationSearchBar(),
          ),

          // Bottom: active booking mini-card + bottom nav handled by shell
        ],
      ),
    );
  }
}
```

### Card Grid Screen (Services Tab)

```dart
class ServicesScreen extends ConsumerWidget {
  const ServicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final categories = ref.watch(serviceCategoriesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.servicesTitle, style: MyShopTypography.h1)),
      body: categories.when(
        loading: () => const ServiceCategoriesSkeletonLoader(),
        error: (e, _) => ErrorStateWidget(
          message: l10n.errorLoadingServices,
          onRetry: () => ref.invalidate(serviceCategoriesProvider),
        ),
        data: (cats) => GridView.builder(
          padding: MyShopSpacing.screenAll,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: MyShopSpacing.md,
            crossAxisSpacing: MyShopSpacing.md,
            childAspectRatio: 0.85,
          ),
          itemCount: cats.length,
          itemBuilder: (context, index) => ServiceCategoryCard(
            category: cats[index],
            onTap: () => context.push('/services/request/${cats[index].id}'),
          ),
        ),
      ),
    );
  }
}
```

### List Screen (Activity / History)

```dart
class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final activities = ref.watch(activityProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.activityTitle, style: MyShopTypography.h1)),
      body: activities.when(
        loading: () => const ActivitySkeletonLoader(),
        error: (e, _) => ErrorStateWidget(
          message: l10n.errorLoadingActivity,
          onRetry: () => ref.invalidate(activityProvider),
        ),
        data: (items) => items.isEmpty
            ? EmptyStateWidget(
                title: l10n.noActivityTitle,
                description: l10n.noActivityDescription,
              )
            : ListView.separated(
                padding: MyShopSpacing.screenAll,
                itemCount: items.length,
                separatorBuilder: (_, __) => MyShopSpacing.itemGap,
                itemBuilder: (context, index) => ActivityCard(activity: items[index]),
              ),
      ),
    );
  }
}
```

---

## Figma-to-Flutter Quick Reference

| Figma Concept | Flutter Widget |
|---------------|---------------|
| Auto Layout (horizontal) | `Row` |
| Auto Layout (vertical) | `Column` |
| Auto Layout (wrap) | `Wrap` |
| Frame with fixed size | `SizedBox` |
| Frame with fill | `Expanded` / `Flexible` |
| Frame with scroll | `SingleChildScrollView` / `ListView` |
| Absolute positioned | `Stack` + `Positioned` |
| Component instance | Extract to reusable widget |
| Border radius | `BorderRadius.circular(value)` |
| Drop shadow | `BoxDecoration(boxShadow: [...])` |
| Gradient fill | `BoxDecoration(gradient: LinearGradient(...))` |
| Image fill | `Image.asset` / `CachedNetworkImage` |
| Icon | `Icon` from Lucide, Material, or custom SVG |
