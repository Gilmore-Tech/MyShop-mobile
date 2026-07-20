import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../providers/emergency_contacts_provider.dart';

class ProviderEmergencyContactsScreen extends ConsumerWidget {
  const ProviderEmergencyContactsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(providerEmergencyContactsProvider);
    final notifier = ref.read(providerEmergencyContactsProvider.notifier);

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      appBar: AppBar(
        backgroundColor: MyShopColors.surfaceWhite,
        foregroundColor: MyShopColors.textPrimary,
        title: const Text('Emergency Contacts'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: context.pop,
        ),
      ),
      body: RefreshIndicator(
        onRefresh: notifier.load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(MyShopSpacing.md),
          children: [
            const _RoleSafetyNotice(),
            if (state.error != null) ...[
              const SizedBox(height: MyShopSpacing.sm),
              _ErrorNotice(message: state.error!),
            ],
            const SizedBox(height: MyShopSpacing.md),
            if (state.loading)
              const Padding(
                padding: EdgeInsets.all(MyShopSpacing.xl),
                child: Center(
                  child: CircularProgressIndicator(
                    color: MyShopColors.primaryGold,
                  ),
                ),
              )
            else if (state.contacts.isEmpty)
              const _EmptyContacts()
            else
              ...state.contacts.map(
                (contact) => _ContactCard(
                  contact: contact,
                  deleting: state.deletingId == contact.id,
                  onDelete: () => _confirmDelete(
                    context,
                    notifier,
                    contact,
                  ),
                ),
              ),
            const SizedBox(height: MyShopSpacing.md),
            if (!state.loading && state.contacts.length < 3)
              OutlinedButton.icon(
                onPressed: state.saving
                    ? null
                    : () => _showAddDialog(context, notifier),
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: Text(
                  state.saving ? 'Saving…' : 'Add emergency contact',
                ),
              ),
            const SizedBox(height: MyShopSpacing.sm),
            Text(
              '${state.contacts.length} of 3 contacts added for this provider role.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: MyShopColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddDialog(
    BuildContext context,
    ProviderEmergencyContactsNotifier notifier,
  ) async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final relationship = TextEditingController();
    final formKey = GlobalKey<FormState>();

    try {
      final submitted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Add emergency contact'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Full name'),
                    validator: (value) => (value?.trim().length ?? 0) < 2
                        ? 'Enter the contact name'
                        : null,
                  ),
                  TextFormField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Ghana phone number',
                    ),
                    validator: (value) =>
                        Validators.ghanaPhone(value?.trim() ?? ''),
                  ),
                  TextFormField(
                    controller: relationship,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Relationship (optional)',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() == true) {
                  Navigator.of(dialogContext).pop(true);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (submitted != true) return;

      final saved = await notifier.add(
        name: name.text.trim(),
        phone: phone.text.trim(),
        relationship: relationship.text.trim().isEmpty
            ? 'Contact'
            : relationship.text.trim(),
      );
      if (!saved && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contact was not saved. Please retry.')),
        );
      }
    } finally {
      name.dispose();
      phone.dispose();
      relationship.dispose();
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    ProviderEmergencyContactsNotifier notifier,
    ProviderEmergencyContact contact,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove emergency contact?'),
        content: Text(
          '${contact.name} will no longer receive SOS location alerts for this provider role.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep contact'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: MyShopColors.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) await notifier.remove(contact.id);
  }
}

class _RoleSafetyNotice extends StatelessWidget {
  const _RoleSafetyNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: MyShopColors.errorLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.error.withAlpha(60)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.emergency_rounded, color: MyShopColors.error),
          SizedBox(width: MyShopSpacing.sm),
          Expanded(
            child: Text(
              'These contacts belong only to your current driver or artisan account. They receive your location when you raise an in-app SOS.',
              style: TextStyle(color: MyShopColors.error, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.sm),
      decoration: BoxDecoration(
        color: MyShopColors.warning.withAlpha(25),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(message, style: const TextStyle(color: MyShopColors.warning)),
    );
  }
}

class _EmptyContacts extends StatelessWidget {
  const _EmptyContacts();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: MyShopSpacing.xl),
      child: Column(
        children: [
          Icon(
            Icons.people_outline_rounded,
            size: 56,
            color: MyShopColors.textSecondary,
          ),
          SizedBox(height: MyShopSpacing.sm),
          Text(
            'No contacts added for this role yet',
            style: TextStyle(color: MyShopColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({
    required this.contact,
    required this.deleting,
    required this.onDelete,
  });

  final ProviderEmergencyContact contact;
  final bool deleting;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: MyShopSpacing.sm),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: MyShopColors.errorLight,
          foregroundColor: MyShopColors.error,
          child: Icon(
            contact.isPrimary ? Icons.star_rounded : Icons.emergency_rounded,
          ),
        ),
        title: Text(
          contact.name,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text('${contact.phone}\n${contact.relationship}'),
        isThreeLine: true,
        trailing: deleting
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : IconButton(
                tooltip: 'Remove contact',
                icon: const Icon(Icons.delete_outline_rounded),
                color: MyShopColors.error,
                onPressed: onDelete,
              ),
      ),
    );
  }
}
