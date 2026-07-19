import 'package:flutter_riverpod/flutter_riverpod.dart';

class ProviderLocationNotice {
  const ProviderLocationNotice({
    required this.bookingId,
    required this.bookingType,
    required this.escalated,
  });

  final String bookingId;
  final String bookingType;
  final bool escalated;

  ProviderLocationNotice copyWith({bool? escalated}) {
    return ProviderLocationNotice(
      bookingId: bookingId,
      bookingType: bookingType,
      escalated: escalated ?? this.escalated,
    );
  }
}

final providerLocationNoticeProvider =
    StateProvider<ProviderLocationNotice?>((_) => null);
