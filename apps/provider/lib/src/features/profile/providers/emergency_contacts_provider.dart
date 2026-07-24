import 'package:api_client/mobile_diagnostics.dart' as developer;

import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';

class ProviderEmergencyContact {
  const ProviderEmergencyContact({
    required this.id,
    required this.name,
    required this.phone,
    required this.relationship,
    required this.isPrimary,
  });

  final String id;
  final String name;
  final String phone;
  final String relationship;
  final bool isPrimary;

  factory ProviderEmergencyContact.fromJson(Map<String, dynamic> json) {
    return ProviderEmergencyContact(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      relationship: json['relationship'] as String? ?? 'Contact',
      isPrimary: json['isPrimary'] as bool? ?? false,
    );
  }
}

class ProviderEmergencyContactsState {
  const ProviderEmergencyContactsState({
    this.contacts = const [],
    this.loading = false,
    this.saving = false,
    this.deletingId,
    this.error,
  });

  final List<ProviderEmergencyContact> contacts;
  final bool loading;
  final bool saving;
  final String? deletingId;
  final String? error;

  ProviderEmergencyContactsState copyWith({
    List<ProviderEmergencyContact>? contacts,
    bool? loading,
    bool? saving,
    String? deletingId,
    bool clearDeleting = false,
    String? error,
    bool clearError = false,
  }) {
    return ProviderEmergencyContactsState(
      contacts: contacts ?? this.contacts,
      loading: loading ?? this.loading,
      saving: saving ?? this.saving,
      deletingId: clearDeleting ? null : (deletingId ?? this.deletingId),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class ProviderEmergencyContactsNotifier
    extends StateNotifier<ProviderEmergencyContactsState> {
  ProviderEmergencyContactsNotifier(this._ref)
      : super(const ProviderEmergencyContactsState()) {
    load();
  }

  final Ref _ref;

  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final raw = await _ref.read(userServiceProvider).getEmergencyContacts();
      final contacts = raw
          .cast<Map<String, dynamic>>()
          .map(ProviderEmergencyContact.fromJson)
          .toList()
        ..sort((a, b) {
          if (a.isPrimary == b.isPrimary) return a.name.compareTo(b.name);
          return a.isPrimary ? -1 : 1;
        });
      state = state.copyWith(contacts: contacts, loading: false);
    } catch (error) {
      developer.debugLog(
        () => 'Provider emergency-contact load failed: $error',
        name: 'ProviderEmergencyContacts',
      );
      state = state.copyWith(
        loading: false,
        error: _roleContactError(error),
      );
    }
  }

  Future<bool> add({
    required String name,
    required String phone,
    required String relationship,
  }) async {
    if (state.saving || state.contacts.length >= 3) return false;
    state = state.copyWith(saving: true, clearError: true);
    try {
      final json = await _ref.read(userServiceProvider).createEmergencyContact(
            name: name,
            phone: phone,
            relationship: relationship,
            isPrimary: state.contacts.isEmpty,
          );
      final contact = ProviderEmergencyContact.fromJson(json);
      state = state.copyWith(
        contacts: [...state.contacts, contact],
        saving: false,
      );
      return true;
    } catch (error) {
      developer.debugLog(
        () => 'Provider emergency-contact create failed: $error',
        name: 'ProviderEmergencyContacts',
      );
      state = state.copyWith(
        saving: false,
        error: _roleContactError(error),
      );
      return false;
    }
  }

  Future<void> remove(String contactId) async {
    if (state.deletingId != null) return;
    state = state.copyWith(deletingId: contactId, clearError: true);
    try {
      await _ref.read(userServiceProvider).deleteEmergencyContact(contactId);
      state = state.copyWith(
        contacts:
            state.contacts.where((contact) => contact.id != contactId).toList(),
        clearDeleting: true,
      );
    } catch (error) {
      developer.debugLog(
        () => 'Provider emergency-contact delete failed: $error',
        name: 'ProviderEmergencyContacts',
      );
      state = state.copyWith(
        clearDeleting: true,
        error: _roleContactError(error),
      );
    }
  }
}

String _roleContactError(Object error) {
  if (error is ApiException &&
      const {
        'ROLE_ACCOUNT_REQUIRED',
        'ROLE_OWNERSHIP_MAPPING_REQUIRED',
        'ROLE_OWNERSHIP_MIGRATION_REQUIRED',
        'EMERGENCY_CONTACT_ROLE_OWNERSHIP_REQUIRED',
      }.contains(error.errorCode)) {
    return 'Your contacts need a secure role-account review. Contact support before relying on in-app SOS alerts.';
  }
  return 'Emergency contacts could not be updated. Please try again.';
}

final providerEmergencyContactsProvider = StateNotifierProvider.autoDispose<
    ProviderEmergencyContactsNotifier, ProviderEmergencyContactsState>(
  ProviderEmergencyContactsNotifier.new,
);
