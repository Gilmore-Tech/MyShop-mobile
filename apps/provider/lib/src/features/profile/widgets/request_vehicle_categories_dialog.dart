import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../providers/provider_vehicle_provider.dart';

class RequestVehicleCategoriesDialog extends ConsumerStatefulWidget {
  const RequestVehicleCategoriesDialog({super.key, required this.vehicle});
  final ProviderVehicle vehicle;

  @override
  ConsumerState<RequestVehicleCategoriesDialog> createState() =>
      _RequestVehicleCategoriesDialogState();
}

class _RequestVehicleCategoriesDialogState
    extends ConsumerState<RequestVehicleCategoriesDialog> {
  final _selected = <String>{};
  bool _saving = false;
  bool _stale = false;
  String? _error;

  Future<void> _submit() async {
    if (_saving || _selected.isEmpty || _stale) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(providerVehicleServiceProvider).requestCategories(
            vehicleId: widget.vehicle.id,
            expectedVersion: widget.vehicle.version,
            rideCategoryIds: _selected.toList(growable: false),
          );
      ref.invalidate(providerVehiclesProvider);
      if (mounted) {
        Navigator.pop(context);
        MyShopToast.show(context,
            message: 'Category request sent to your Regional Manager.');
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _stale = error.errorCode == 'VEHICLE_CHANGED_RETRY' ||
            error.errorCode == 'VEHICLE_REVISION_ALREADY_PENDING';
        _error = _stale
            ? 'Your vehicle changed or has a change under review. Close this window and reload your vehicles.'
            : 'Could not send this request. Check your connection and try again.';
      });
      if (_stale) ref.invalidate(providerVehiclesProvider);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Could not confirm this request. Reload your vehicles before trying again.');
        ref.invalidate(providerVehiclesProvider);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = ref.watch(providerVehicleRideCategoriesProvider);
    final unavailable = widget.vehicle.rideCategories
        .where((row) => row.status != ProviderVehicleCategoryStatus.rejected)
        .map((row) => row.id)
        .toSet();
    return AlertDialog(
      title: const Text('Request ride categories'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                    'Choose additional categories for this vehicle. Your Regional Manager must approve them before you receive those requests.'),
                const SizedBox(height: MyShopSpacing.md),
                options.when(
                  loading: () =>
                      Container(height: 100, color: MyShopColors.surfaceGrey),
                  error: (_, __) => Column(children: [
                    const Text('Could not load categories.'),
                    TextButton(
                        onPressed: () => ref
                            .invalidate(providerVehicleRideCategoriesProvider),
                        child: const Text('Retry')),
                  ]),
                  data: (choices) {
                    final available = choices
                        .where((c) => !unavailable.contains(c.id))
                        .toList();
                    if (available.isEmpty) {
                      return const Text(
                          'All available categories are already approved or awaiting review.');
                    }
                    return Column(mainAxisSize: MainAxisSize.min, children: [
                      for (final choice in available)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(choice.name),
                          value: _selected.contains(choice.id),
                          onChanged: _saving || _stale
                              ? null
                              : (checked) => setState(() {
                                    if (checked == true) {
                                      _selected.add(choice.id);
                                    } else {
                                      _selected.remove(choice.id);
                                    }
                                  }),
                        ),
                    ]);
                  },
                ),
                if (_error != null)
                  Text(_error!,
                      style: const TextStyle(color: MyShopColors.error)),
              ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Close')),
        TextButton(
            onPressed: _selected.isEmpty || _saving || _stale ? null : _submit,
            child: Text(_saving ? 'Sending…' : 'Send request')),
      ],
    );
  }
}
