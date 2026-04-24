import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';

// ── Payment Method Type ───────────────────────────────────────────────────────

enum PaymentMethodType { momo, card }

extension PaymentMethodTypeX on PaymentMethodType {
  IconData get icon => switch (this) {
        PaymentMethodType.momo => Icons.phone_android_rounded,
        PaymentMethodType.card => Icons.credit_card_rounded,
      };
}

// ── Momo Provider ─────────────────────────────────────────────────────────────

enum MomoProvider { mtn, vodafone, airteltigo }

extension MomoProviderX on MomoProvider {
  String get label => switch (this) {
        MomoProvider.mtn        => 'MTN MoMo',
        MomoProvider.vodafone   => 'Vodafone Cash',
        MomoProvider.airteltigo => 'AirtelTigo Money',
      };

  String get apiValue => switch (this) {
        MomoProvider.mtn        => 'mtn',
        MomoProvider.vodafone   => 'vodafone',
        MomoProvider.airteltigo => 'airteltigo',
      };

  Color get color => switch (this) {
        MomoProvider.mtn        => const Color(0xFFF5A623),
        MomoProvider.vodafone   => const Color(0xFFEB5757),
        MomoProvider.airteltigo => const Color(0xFF27AE60),
      };

  Color get bgColor => switch (this) {
        MomoProvider.mtn        => const Color(0xFFFFF8EC),
        MomoProvider.vodafone   => const Color(0xFFFFF0F0),
        MomoProvider.airteltigo => const Color(0xFFEBFAF2),
      };
}

MomoProvider? _parseMomoProvider(String? raw) => switch (raw?.toLowerCase()) {
      'mtn'        => MomoProvider.mtn,
      'vodafone'   => MomoProvider.vodafone,
      'airteltigo' => MomoProvider.airteltigo,
      _            => null,
    };

// ── Payment Method ────────────────────────────────────────────────────────────

class PaymentMethod {
  final String            id;
  final PaymentMethodType type;
  final MomoProvider?     momoProvider;
  final String            title;
  final String            subtitle;
  final bool              isDefault;

  const PaymentMethod({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.isDefault,
    this.momoProvider,
  });

  factory PaymentMethod.fromJson(Map<String, dynamic> json) {
    final typeRaw = json['type'] as String? ?? '';
    final isMomo  = typeRaw == 'momo';
    final momoP   = _parseMomoProvider(json['provider'] as String?);

    String title;
    String subtitle;

    if (isMomo && momoP != null) {
      title    = momoP.label;
      subtitle = json['phone'] as String? ?? '';
    } else {
      final brand = json['brand'] as String? ?? 'Card';
      final last4 = json['last4'] as String? ?? '••••';
      final exp   = json['expiresAt'] as String? ?? '';
      title       = '$brand  ••••  $last4';
      subtitle    = exp.isNotEmpty ? 'Expires $exp' : '';
    }

    return PaymentMethod(
      id:           json['id'] as String,
      type:         isMomo ? PaymentMethodType.momo : PaymentMethodType.card,
      momoProvider: momoP,
      title:        title,
      subtitle:     subtitle,
      isDefault:    json['isDefault'] as bool? ?? false,
    );
  }
}

// ── State ─────────────────────────────────────────────────────────────────────

class PaymentMethodsState {
  final List<PaymentMethod> methods;
  final bool                isLoading;
  final String?             deletingId;
  final String?             settingDefaultId;
  final String?             errorMessage;

  const PaymentMethodsState({
    this.methods          = const [],
    this.isLoading        = false,
    this.deletingId,
    this.settingDefaultId,
    this.errorMessage,
  });

  bool get isDeletingAny   => deletingId != null;
  bool get isSettingDefault => settingDefaultId != null;

  List<PaymentMethod> get momoMethods =>
      methods.where((m) => m.type == PaymentMethodType.momo).toList();

  List<PaymentMethod> get cardMethods =>
      methods.where((m) => m.type == PaymentMethodType.card).toList();

  PaymentMethodsState copyWith({
    List<PaymentMethod>? methods,
    bool?                isLoading,
    String?              deletingId,
    String?              settingDefaultId,
    String?              errorMessage,
    bool                 clearDeleting         = false,
    bool                 clearSettingDefault   = false,
    bool                 clearError            = false,
  }) =>
      PaymentMethodsState(
        methods:          methods         ?? this.methods,
        isLoading:        isLoading       ?? this.isLoading,
        deletingId:       clearDeleting        ? null : (deletingId       ?? this.deletingId),
        settingDefaultId: clearSettingDefault  ? null : (settingDefaultId ?? this.settingDefaultId),
        errorMessage:     clearError           ? null : (errorMessage     ?? this.errorMessage),
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class PaymentMethodsNotifier extends StateNotifier<PaymentMethodsState> {
  PaymentMethodsNotifier(this._ref) : super(const PaymentMethodsState()) {
    _load();
  }

  final Ref _ref;

  Future<void> _load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final raw     = await _ref.read(paymentServiceProvider).getPaymentMethods();
      final methods = raw
          .cast<Map<String, dynamic>>()
          .map(PaymentMethod.fromJson)
          .toList();
      state = state.copyWith(methods: methods, isLoading: false);
    } catch (e) {
      developer.log('getPaymentMethods error: $e', name: 'PaymentMethods');
      state = state.copyWith(
        isLoading:    false,
        errorMessage: 'Could not load payment methods',
      );
    }
  }

  Future<void> reload() => _load();

  Future<void> setDefault(String id) async {
    if (state.isSettingDefault) return;
    state = state.copyWith(settingDefaultId: id, clearError: true);
    try {
      await _ref.read(paymentServiceProvider).setDefaultMethod(id);
      final updated = state.methods.map((m) {
        return PaymentMethod(
          id:           m.id,
          type:         m.type,
          momoProvider: m.momoProvider,
          title:        m.title,
          subtitle:     m.subtitle,
          isDefault:    m.id == id,
        );
      }).toList();
      state = state.copyWith(methods: updated, clearSettingDefault: true);
    } catch (e) {
      developer.log('setDefaultMethod error: $e', name: 'PaymentMethods');
      state = state.copyWith(
        clearSettingDefault: true,
        errorMessage: 'Could not update default. Please try again.',
      );
    }
  }

  Future<void> deleteMethod(String id) async {
    if (state.isDeletingAny) return;
    state = state.copyWith(deletingId: id, clearError: true);
    try {
      await _ref.read(paymentServiceProvider).deletePaymentMethod(id);
      state = state.copyWith(
        methods:        state.methods.where((m) => m.id != id).toList(),
        clearDeleting:  true,
      );
    } catch (e) {
      developer.log('deletePaymentMethod error: $e', name: 'PaymentMethods');
      state = state.copyWith(
        clearDeleting: true,
        errorMessage:  'Could not remove method. Please try again.',
      );
    }
  }

  Future<bool> addMomo({
    required MomoProvider provider,
    required String phone,
  }) async {
    try {
      final json = await _ref.read(paymentServiceProvider).addMomoMethod(
            provider: provider.apiValue,
            phone:    phone,
          );
      final method = PaymentMethod.fromJson(json);
      state = state.copyWith(methods: [...state.methods, method]);
      return true;
    } catch (e) {
      developer.log('addMomoMethod error: $e', name: 'PaymentMethods');
      state = state.copyWith(errorMessage: 'Could not add method. Please try again.');
      return false;
    }
  }
}

final paymentMethodsProvider = StateNotifierProvider.autoDispose<
    PaymentMethodsNotifier, PaymentMethodsState>(
  (ref) => PaymentMethodsNotifier(ref),
);
