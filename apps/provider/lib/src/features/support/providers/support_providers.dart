import 'dart:async';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart' show SupportLegalAsync;

import '../../../core/di/providers.dart';
import '../../../core/providers/service_notice_provider.dart';
import '../../auth/providers/auth_controller.dart';
import '../../profile/providers/provider_type_provider.dart';

const SupportAudience kProviderSupportAudience = SupportAudience.provider;

/// Audience used for legal documents only. Drivers and artisans see
/// role-specific Terms; help articles and tickets keep the broader
/// [kProviderSupportAudience]. Backend cascades driver→provider→both and
/// artisan→provider→both, so a combined provider doc is still served when
/// no role-specific version exists.
final legalAudienceProvider = Provider<SupportAudience>((ref) {
  final type = ref.watch(providerTypeProvider);
  return type.isDriver ? SupportAudience.driver : SupportAudience.artisan;
});

final supportServiceProvider = Provider<SupportService>((ref) {
  return SupportService(ref.watch(dioProvider));
});

final helpServiceProvider = Provider<HelpService>((ref) {
  return HelpService(ref.watch(dioProvider));
});

final legalServiceProvider = Provider<LegalService>((ref) {
  return LegalService(ref.watch(dioProvider));
});

final providerRoleSessionIdentityProvider =
    FutureProvider.autoDispose<RoleSessionIdentity?>((ref) async {
  ref.watch(serviceNoticeProvider.select((state) => state.recoveryEpoch));
  final auth = ref.watch(authControllerProvider);
  if (auth is! AuthAuthenticated) return null;

  final (expectedRole, roleAccountId) = switch (auth.user.role) {
    AuthRole.driver => ('driver', auth.user.driverProfile?.id),
    AuthRole.artisan => ('artisan', auth.user.artisanProfile?.id),
    AuthRole.client => (null, null),
  };
  if (expectedRole == null ||
      roleAccountId == null ||
      roleAccountId.isEmpty ||
      auth.user.id != roleAccountId) {
    throw const FormatException('Invalid provider role account identity.');
  }
  final token = await ref.read(tokenStorageProvider).readAccessToken();
  final identity = RoleSessionIdentity.tryParseAccessToken(token);
  if (identity == null ||
      identity.role != expectedRole ||
      identity.roleAccountId != roleAccountId) {
    throw const FormatException('Invalid provider role-session identity.');
  }
  return identity;
});

final legalConsentStatusProvider =
    FutureProvider.autoDispose<ScopedLegalConsentStatus?>((ref) async {
  final identity = await ref.watch(providerRoleSessionIdentityProvider.future);
  if (identity == null) return null;
  final status = await ref.read(legalServiceProvider).getConsentStatus();
  if (status.role != identity.role) {
    throw const FormatException('Consent status role mismatch.');
  }
  Timer? refresh;
  if (status.requiresConsent && status.hasActiveWork) {
    refresh = Timer(const Duration(seconds: 60), ref.invalidateSelf);
  }
  ref.onDispose(() => refresh?.cancel());
  return ScopedLegalConsentStatus(identity: identity, status: status);
});

/// Returns only a successful response owned by the exact current provider
/// role-account session. Unknown/loading/error states never imply that consent
/// is missing.
LegalConsentStatus? usableProviderLegalConsentStatus(
  AuthState auth,
  AsyncValue<RoleSessionIdentity?>? currentIdentity,
  AsyncValue<ScopedLegalConsentStatus?>? scoped,
) {
  if (auth is! AuthAuthenticated ||
      currentIdentity == null ||
      currentIdentity.isLoading ||
      currentIdentity.hasError ||
      scoped == null ||
      scoped.isLoading ||
      scoped.hasError) {
    return null;
  }
  final (role, roleAccountId) = switch (auth.user.role) {
    AuthRole.driver => ('driver', auth.user.driverProfile?.id),
    AuthRole.artisan => ('artisan', auth.user.artisanProfile?.id),
    AuthRole.client => (null, null),
  };
  final identity = currentIdentity.valueOrNull;
  final snapshot = scoped.valueOrNull;
  if (role == null ||
      roleAccountId == null ||
      auth.user.id != roleAccountId ||
      identity == null ||
      identity.role != role ||
      identity.roleAccountId != roleAccountId ||
      snapshot == null ||
      !snapshot.belongsTo(identity)) {
    return null;
  }
  return snapshot.status;
}

final helpCategoriesProvider =
    AsyncNotifierProvider<HelpCategoriesNotifier, List<HelpCategory>>(
  HelpCategoriesNotifier.new,
);

class HelpCategoriesNotifier extends AsyncNotifier<List<HelpCategory>> {
  @override
  Future<List<HelpCategory>> build() async {
    return ref
        .read(helpServiceProvider)
        .listCategories(audience: kProviderSupportAudience);
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref
          .read(helpServiceProvider)
          .listCategories(audience: kProviderSupportAudience),
    );
  }
}

final helpArticlesProvider = FutureProvider.autoDispose
    .family<List<HelpArticle>, String>((ref, categorySlug) {
  return ref.read(helpServiceProvider).listArticles(
        categorySlug: categorySlug,
        audience: kProviderSupportAudience,
      );
});

final helpArticleProvider =
    FutureProvider.autoDispose.family<HelpArticle, String>((ref, slug) {
  return ref.read(helpServiceProvider).getArticle(
        slug: slug,
        audience: kProviderSupportAudience,
      );
});

final legalDocumentProvider =
    FutureProvider.family<LegalDocument, String>((ref, slug) {
  ref.keepAlive();
  final audience = ref.watch(legalAudienceProvider);
  return ref.read(legalServiceProvider).getDocument(
        slug: slug,
        audience: audience,
      );
});

class TicketsListState {
  const TicketsListState({
    this.tickets = const [],
    this.nextCursor,
    this.loadingMore = false,
  });

  final List<SupportTicket> tickets;
  final String? nextCursor;
  final bool loadingMore;

  bool get hasMore => nextCursor != null;

  TicketsListState copyWith({
    List<SupportTicket>? tickets,
    String? nextCursor,
    bool? loadingMore,
    bool clearCursor = false,
  }) {
    return TicketsListState(
      tickets: tickets ?? this.tickets,
      nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
      loadingMore: loadingMore ?? this.loadingMore,
    );
  }
}

final ticketsListProvider =
    AsyncNotifierProvider<TicketsListNotifier, TicketsListState>(
  TicketsListNotifier.new,
);

class TicketsListNotifier extends AsyncNotifier<TicketsListState> {
  @override
  Future<TicketsListState> build() async {
    final page = await ref.read(supportServiceProvider).listTickets();
    return TicketsListState(
      tickets: page.items,
      nextCursor: page.nextCursor,
    );
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final page = await ref.read(supportServiceProvider).listTickets();
      return TicketsListState(
        tickets: page.items,
        nextCursor: page.nextCursor,
      );
    });
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    state = AsyncValue.data(current.copyWith(loadingMore: true));
    try {
      final page = await ref.read(supportServiceProvider).listTickets(
            cursor: current.nextCursor,
          );
      state = AsyncValue.data(
        current.copyWith(
          tickets: [...current.tickets, ...page.items],
          nextCursor: page.nextCursor,
          loadingMore: false,
          clearCursor: page.nextCursor == null,
        ),
      );
    } catch (_) {
      state = AsyncValue.data(current.copyWith(loadingMore: false));
    }
  }

  void prepend(SupportTicket ticket) {
    final current = state.value;
    if (current == null) return;
    final filtered = current.tickets.where((t) => t.id != ticket.id);
    state = AsyncValue.data(
      current.copyWith(tickets: [ticket, ...filtered]),
    );
  }
}

class TicketDetailState {
  const TicketDetailState({
    this.ticket,
    this.messages = const [],
    this.nextCursor,
  });

  final SupportTicket? ticket;
  final List<TicketMessage> messages;
  final String? nextCursor;

  TicketDetailState copyWith({
    SupportTicket? ticket,
    List<TicketMessage>? messages,
    String? nextCursor,
  }) {
    return TicketDetailState(
      ticket: ticket ?? this.ticket,
      messages: messages ?? this.messages,
      nextCursor: nextCursor ?? this.nextCursor,
    );
  }
}

final ticketDetailProvider = AsyncNotifierProvider.family<TicketDetailNotifier,
    TicketDetailState, String>(
  TicketDetailNotifier.new,
);

class TicketDetailNotifier
    extends FamilyAsyncNotifier<TicketDetailState, String> {
  @override
  Future<TicketDetailState> build(String ticketId) async {
    final svc = ref.read(supportServiceProvider);
    final results = await Future.wait([
      svc.getTicket(ticketId),
      svc.getMessages(ticketId),
    ]);
    final ticket = results[0] as SupportTicket;
    final page = results[1] as TicketPage<TicketMessage>;
    if (page.items.isNotEmpty) {
      svc
          .markRead(ticketId, upToMessageId: page.items.last.id)
          .catchError((_) {});
    }
    return TicketDetailState(
      ticket: ticket,
      messages: page.items,
      nextCursor: page.nextCursor,
    );
  }

  Future<void> sendMessage(String body) async {
    final current = state.value;
    if (current == null) return;
    final tmpId = 'tmp_${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = TicketMessage(
      id: tmpId,
      ticketId: arg,
      senderRole: TicketSenderRole.user,
      body: body,
      createdAt: DateTime.now().toUtc(),
    );
    state = AsyncValue.data(
      current.copyWith(messages: [...current.messages, optimistic]),
    );
    try {
      final saved = await ref.read(supportServiceProvider).postMessage(
            arg,
            PostTicketMessageRequest(body: body),
          );
      final next = state.value ?? current;
      state = AsyncValue.data(
        next.copyWith(
          messages: next.messages
              .map((m) => m.id == tmpId ? saved : m)
              .toList(growable: false),
        ),
      );
    } catch (e) {
      final next = state.value ?? current;
      state = AsyncValue.data(
        next.copyWith(
          messages:
              next.messages.where((m) => m.id != tmpId).toList(growable: false),
        ),
      );
      rethrow;
    }
  }

  Future<void> setStatus(String status) async {
    final updated = await ref.read(supportServiceProvider).updateStatus(
          arg,
          UpdateTicketStatusRequest(status: status),
        );
    final next = state.value ?? const TicketDetailState();
    state = AsyncValue.data(next.copyWith(ticket: updated));
    ref.read(ticketsListProvider.notifier).prepend(updated);
  }
}

final createTicketControllerProvider = Provider<CreateTicketController>(
  (ref) => CreateTicketController(ref),
);

class CreateTicketController {
  CreateTicketController(this._ref);

  final Ref _ref;

  Future<SupportTicket> submit({
    required TicketCategory category,
    required String subject,
    required String description,
    required List<File> attachments,
    String? referenceType,
    String? referenceId,
  }) async {
    final media = _ref.read(mediaServiceProvider);
    final uploaded = <TicketAttachment>[];
    for (final file in attachments) {
      final result = await media.uploadSupportAttachment(file.path);
      uploaded.add(
        TicketAttachment(
          url: result.url,
          mime: result.mimeType,
          sizeBytes: result.sizeBytes,
          filename: file.uri.pathSegments.isNotEmpty
              ? file.uri.pathSegments.last
              : null,
        ),
      );
    }
    final ticket = await _ref.read(supportServiceProvider).createTicket(
          CreateTicketRequest(
            category: category,
            subject: subject,
            description: description,
            attachments: uploaded,
            referenceType: referenceType,
            referenceId: referenceId,
          ),
        );
    _ref.read(ticketsListProvider.notifier).prepend(ticket);
    return ticket;
  }
}

SupportLegalAsync<T> asSupportAsync<T>(AsyncValue<T> v) {
  return v.when(
    data: SupportLegalAsync<T>.data,
    loading: SupportLegalAsync<T>.loading,
    error: (e, _) => SupportLegalAsync<T>.error(e),
  );
}
