import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/services_provider.dart';

class JobTownshipPicker extends ConsumerWidget {
  const JobTownshipPicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(jobCatalogueTownshipProvider).valueOrNull;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ref.watch(jobTownshipsProvider).when(
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => TextButton(
              onPressed: () => ref.invalidate(jobTownshipsProvider),
              child: const Text('Retry loading townships'),
            ),
            data: (townships) => DropdownButton<String>(
              isExpanded: true,
              hint:
                  const Text('Choose the township where you need the service'),
              value:
                  townships.any((town) => town.id == current) ? current : null,
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text('Use my current location'),
                ),
                for (final town in townships)
                  DropdownMenuItem(
                      value: town.id,
                      child: Text(town.serviceAreaName ?? town.name)),
              ],
              onChanged: (id) => ref
                  .read(selectedJobTownshipProvider.notifier)
                  .state = id == '' ? null : id,
            ),
          ),
    );
  }
}
