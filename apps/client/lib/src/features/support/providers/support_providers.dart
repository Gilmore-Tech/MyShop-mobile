import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart' show SupportLegalAsync;

import '../../../core/di/providers.dart';

// ── Audience ─────────────────────────────────────────────────────────────────
// The client app talks to the `client` audience for help articles + legal
// docs + ticket category filtering.
const SupportAudience kClientSupportAudience = SupportAudience.client;

// ── Service providers ────────────────────────────────────────────────────────

final supportServiceProvider = Provider<SupportService>((ref) {
  return SupportService(ref.watch(dioProvider));
});

final helpServiceProvider = Provider<HelpService>((ref) {
  return HelpService(ref.watch(dioProvider));
});

final legalServiceProvider = Provider<LegalService>((ref) {
  return LegalService(ref.watch(dioProvider));
});

// ── Help categories (support home) ───────────────────────────────────────────

final helpCategoriesProvider =
    AsyncNotifierProvider<HelpCategoriesNotifier, List<HelpCategory>>(
  HelpCategoriesNotifier.new,
);

class HelpCategoriesNotifier extends AsyncNotifier<List<HelpCategory>> {
  @override
  Future<List<HelpCategory>> build() async {
    return ref
        .read(helpServiceProvider)
        .listCategories(audience: kClientSupportAudience);
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref
          .read(helpServiceProvider)
          .listCategories(audience: kClientSupportAudience),
    );
  }
}

// ── Help articles (per category) ─────────────────────────────────────────────

final helpArticlesProvider = FutureProvider.autoDispose
    .family<List<HelpArticle>, String>((ref, categorySlug) {
  return ref.read(helpServiceProvider).listArticles(
        categorySlug: categorySlug,
        audience: kClientSupportAudience,
      );
});

final helpArticleProvider =
    FutureProvider.autoDispose.family<HelpArticle, String>((ref, slug) {
  return ref.read(helpServiceProvider).getArticle(
        slug: slug,
        audience: kClientSupportAudience,
      );
});

// ── Legal documents ──────────────────────────────────────────────────────────

final legalDocumentProvider =
    FutureProvider.family<LegalDocument, String>((ref, slug) {
  // keepAlive — legal docs barely change between app sessions.
  ref.keepAlive();
  return ref.read(legalServiceProvider).getDocument(
        slug: slug,
        audience: kClientSupportAudience,
      );
});

// ── Tickets list ─────────────────────────────────────────────────────────────

class TicketsListState {
  const TicketsListState({
    this.tickets = const [],
    this.nextCursor,
    this.loadingMore = false,
    this.error,
  });

  final List<SupportTicket> tickets;
  final String? nextCursor;
  final bool loadingMore;
  final Object? error;

  bool get hasMore => nextCursor != null;

  TicketsListState copyWith({
    List<SupportTicket>? tickets,
    String? nextCursor,
    bool? loadingMore,
    Object? error,
    bool clearCursor = false,
    bool clearError = false,
  }) {
    return TicketsListState(
      tickets: tickets ?? this.tickets,
      nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
      loadingMore: loadingMore ?? this.loadingMore,
      error: clearError ? null : (error ?? this.error),
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
    } catch (e) {
      state = AsyncValue.data(
        current.copyWith(loadingMore: false, error: e),
      );
    }
  }

  /// Inserts (or replaces) a ticket at the top — used after a successful
  /// `createTicket` so the list reflects the new ticket without a refetch.
  void prepend(SupportTicket ticket) {
    final current = state.value;
    if (current == null) return;
    final filtered = current.tickets.where((t) => t.id != ticket.id);
    state = AsyncValue.data(
      current.copyWith(tickets: [ticket, ...filtered]),
    );
  }
}

// ── Ticket detail (header + messages) ────────────────────────────────────────

class TicketDetailState {
  const TicketDetailState({
    this.ticket,
    this.messages = const [],
    this.nextCursor,
    this.loadingMessages = false,
  });

  final SupportTicket? ticket;
  final List<TicketMessage> messages;
  final String? nextCursor;
  final bool loadingMessages;

  TicketDetailState copyWith({
    SupportTicket? ticket,
    List<TicketMessage>? messages,
    String? nextCursor,
    bool? loadingMessages,
    bool clearCursor = false,
  }) {
    return TicketDetailState(
      ticket: ticket ?? this.ticket,
      messages: messages ?? this.messages,
      nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
      loadingMessages: loadingMessages ?? this.loadingMessages,
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
    // Fire-and-forget mark-read on open.
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

  /// Optimistic-insert send. Renders a `tmp_…` bubble immediately, swaps
  /// it for the server-acked message on success, removes it on failure.
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
      final swapped = next.messages
          .map((m) => m.id == tmpId ? saved : m)
          .toList(growable: false);
      state = AsyncValue.data(next.copyWith(messages: swapped));
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
    try {
      final updated = await ref.read(supportServiceProvider).updateStatus(
            arg,
            UpdateTicketStatusRequest(status: status),
          );
      final next = state.value ?? const TicketDetailState();
      state = AsyncValue.data(next.copyWith(ticket: updated));
      // Reflect on the list too.
      ref.read(ticketsListProvider.notifier).prepend(updated);
    } catch (_) {
      rethrow;
    }
  }

  /// Refetch from the FCM tap bridge — when a `support_ticket_message`
  /// push arrives for this ticket, the bridge invalidates this provider.
}

// ── New-ticket submit (with attachment upload) ───────────────────────────────

/// Coordinates: upload attachments → POST ticket → prepend to list.
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

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Maps Riverpod's `AsyncValue<T>` to the dumb-shell-friendly
/// [SupportLegalAsync<T>] used by all support widgets.
SupportLegalAsync<T> asSupportAsync<T>(AsyncValue<T> v) {
  return v.when(
    data: SupportLegalAsync<T>.data,
    loading: SupportLegalAsync<T>.loading,
    error: (e, _) => SupportLegalAsync<T>.error(e),
  );
}
