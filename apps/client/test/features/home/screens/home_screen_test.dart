import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_client/src/core/providers/current_location_label_provider.dart';
import 'package:myshop_client/src/features/home/providers/home_provider.dart';
import 'package:myshop_client/src/features/home/providers/promo_campaigns_provider.dart';
import 'package:myshop_client/src/features/home/screens/home_screen.dart';
import 'package:myshop_client/src/features/profile/providers/profile_provider.dart';

class _FakeAccountNotifier extends AccountScreenNotifier {
  @override
  Future<AccountScreenData> build() async => const AccountScreenData(
        profile: AccountProfile(
          userId: 'client-1',
          displayName: 'Ama Mensah',
          maskedEmail: '',
          maskedPhone: '+233 ••• ••• 227',
          isKycVerified: false,
        ),
        unreadNotificationCount: 0,
      );
}

class _EmptyOffersNotifier extends SpecialOffersNotifier {
  @override
  Future<List<SpecialOffer>> build() async => const [];
}

class _RecentActivityNotifier extends HomeRecentActivityNotifier {
  _RecentActivityNotifier(this.items);

  final List<HomeRecentActivityItem> items;

  @override
  Future<List<HomeRecentActivityItem>> build() async => items;
}

void main() {
  Future<void> pumpHome(
    WidgetTester tester, {
    List<HomeRecentActivityItem> activity = const [],
  }) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountScreenProvider.overrideWith(_FakeAccountNotifier.new),
          currentLocationLabelProvider.overrideWith(
            (_) async => 'Prempeh II Street, Adum, Kumasi, Ghana',
          ),
          specialOffersProvider.overrideWith(_EmptyOffersNotifier.new),
          activePromoCampaignsProvider.overrideWith(
            (_) async => const <ActivePromoCampaign>[],
          ),
          homeRecentActivityProvider.overrideWith(
            () => _RecentActivityNotifier(activity),
          ),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows resolved location and no empty offers placeholder',
      (tester) async {
    await pumpHome(tester);

    expect(
      find.text('Current: Prempeh II Street, Adum, Kumasi, Ghana'),
      findsOneWidget,
    );
    expect(find.text('SPECIAL OFFERS'), findsNothing);
    expect(find.text('RECENT ACTIVITY'), findsOneWidget);
    expect(find.text('Your activity will appear here'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders the approved combined recent activity cards',
      (tester) async {
    await pumpHome(
      tester,
      activity: [
        HomeRecentActivityItem(
          id: 'ride-1',
          type: HomeActivityType.ride,
          title: 'Ride to Ahodwo',
          subtitle: 'Adum → Ahodwo',
          status: HomeActivityStatus.completed,
          createdAt: DateTime.now(),
        ),
        HomeRecentActivityItem(
          id: 'job-1',
          type: HomeActivityType.job,
          title: 'Plumbing',
          subtitle: 'Daban, Kumasi',
          status: HomeActivityStatus.inProgress,
          createdAt: DateTime.now().subtract(const Duration(hours: 1)),
        ),
      ],
    );

    expect(find.text('Ride to Ahodwo'), findsOneWidget);
    expect(find.text('Plumbing'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('In progress'), findsOneWidget);
    expect(find.text('Your activity will appear here'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
