import 'dart:developer' as developer;

import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';

// ── Model ─────────────────────────────────────────────────────────────────────

class EmergencyContact {
  final String id;
  final String name;
  final String phone;
  final String relationship;
  final bool isPrimary;

  const EmergencyContact({
    required this.id,
    required this.name,
    required this.phone,
    required this.relationship,
    this.isPrimary = false,
  });

  static EmergencyContact fromJson(Map<String, dynamic> json) =>
      EmergencyContact(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        relationship: json['relationship'] as String? ?? 'Contact',
        isPrimary: json['isPrimary'] as bool? ?? false,
      );
}

// ── State ─────────────────────────────────────────────────────────────────────

class EmergencyContactsState {
  final List<EmergencyContact> contacts;
  final bool isLoading;
  final bool isSaving;
  final String? deletingId;
  final String? errorMessage;

  const EmergencyContactsState({
    this.contacts = const [],
    this.isLoading = false,
    this.isSaving = false,
    this.deletingId,
    this.errorMessage,
  });

  bool get isDeleting => deletingId != null;

  EmergencyContactsState copyWith({
    List<EmergencyContact>? contacts,
    bool? isLoading,
    bool? isSaving,
    String? deletingId,
    String? errorMessage,
    bool clearError = false,
    bool clearDeleting = false,
  }) =>
      EmergencyContactsState(
        contacts: contacts ?? this.contacts,
        isLoading: isLoading ?? this.isLoading,
        isSaving: isSaving ?? this.isSaving,
        deletingId: clearDeleting ? null : (deletingId ?? this.deletingId),
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class EmergencyContactsNotifier extends StateNotifier<EmergencyContactsState> {
  EmergencyContactsNotifier(this._ref) : super(const EmergencyContactsState()) {
    _load();
  }

  final Ref _ref;

  Future<void> _load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final raw = await _ref.read(userServiceProvider).getEmergencyContacts();
      final contacts = raw
          .cast<Map<String, dynamic>>()
          .map(EmergencyContact.fromJson)
          .toList();
      // Primary contact always first
      contacts.sort((a, b) => b.isPrimary ? 1 : -1);
      state = state.copyWith(contacts: contacts, isLoading: false);
    } catch (e) {
      developer.log('getEmergencyContacts error: $e',
          name: 'EmergencyContacts');
      state = state.copyWith(
        isLoading: false,
        errorMessage: _emergencyContactsError(e),
      );
    }
  }

  Future<void> reload() => _load();

  /// POST /users/me/emergency-contacts
  Future<bool> addContact({
    required String name,
    required String phone,
    String? relationship,
  }) async {
    if (state.isSaving) return false;
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final json = await _ref.read(userServiceProvider).createEmergencyContact(
            name: name,
            phone: phone,
            relationship: relationship,
            isPrimary: state.contacts.isEmpty,
          );
      final contact = EmergencyContact.fromJson(json);
      state = state.copyWith(
        contacts: [...state.contacts, contact],
        isSaving: false,
      );
      return true;
    } catch (e) {
      developer.log('createEmergencyContact error: $e',
          name: 'EmergencyContacts');
      state = state.copyWith(
        isSaving: false,
        errorMessage: 'Could not save contact. Please try again.',
      );
      return false;
    }
  }

  /// DELETE /users/me/emergency-contacts/:id
  Future<void> deleteContact(String id) async {
    if (state.isDeleting) return;
    state = state.copyWith(deletingId: id, clearError: true);
    try {
      await _ref.read(userServiceProvider).deleteEmergencyContact(id);
      state = state.copyWith(
        contacts: state.contacts.where((c) => c.id != id).toList(),
        clearDeleting: true,
      );
    } catch (e) {
      developer.log('deleteEmergencyContact error: $e',
          name: 'EmergencyContacts');
      state = state.copyWith(
        clearDeleting: true,
        errorMessage: 'Could not remove contact. Please try again.',
      );
    }
  }
}

String _emergencyContactsError(Object error) {
  if (error is ApiException &&
      const {
        'ROLE_OWNERSHIP_MAPPING_REQUIRED',
        'ROLE_OWNERSHIP_MIGRATION_REQUIRED',
        'EMERGENCY_CONTACT_ROLE_OWNERSHIP_REQUIRED',
      }.contains(error.errorCode)) {
    return 'Your saved contacts need a secure account review. Contact support before relying on in-app emergency alerts.';
  }
  return 'Could not load emergency contacts. Please try again.';
}

final emergencyContactsProvider = StateNotifierProvider.autoDispose<
    EmergencyContactsNotifier, EmergencyContactsState>(
  (ref) => EmergencyContactsNotifier(ref),
);
