import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

typedef StoreLauncher = Future<bool> Function(Uri uri);

/// Full-screen, non-dismissible gate shown after the API returns the stable
/// `APP_UPDATE_REQUIRED` contract.
class MandatoryAppUpdateScreen extends StatefulWidget {
  const MandatoryAppUpdateScreen({
    super.key,
    required this.message,
    required this.storeUrl,
    this.launchStore,
  });

  final String message;
  final Uri? storeUrl;
  final StoreLauncher? launchStore;

  @override
  State<MandatoryAppUpdateScreen> createState() =>
      _MandatoryAppUpdateScreenState();
}

class _MandatoryAppUpdateScreenState extends State<MandatoryAppUpdateScreen> {
  bool _opening = false;
  String? _error;

  Future<void> _openStore() async {
    final storeUrl = widget.storeUrl;
    if (storeUrl == null || _opening) return;

    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      final launcher = widget.launchStore ??
          (uri) => launchUrl(uri, mode: LaunchMode.externalApplication);
      final opened = await launcher(storeUrl);
      if (!opened && mounted) {
        setState(() {
          _error = 'Could not open the app store. Please try again.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not open the app store. Please try again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _opening = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final missingLink = widget.storeUrl == null;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.system_update_alt_rounded,
                      size: 72,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Update required',
                      textAlign: TextAlign.center,
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.message,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    if (missingLink) ...[
                      const SizedBox(height: 16),
                      Text(
                        'The update link is temporarily unavailable. '
                        'Please contact MyShop support.',
                        key: const Key('mandatory-update-missing-link'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        key: const Key('mandatory-update-launch-error'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        key: const Key('mandatory-update-button'),
                        onPressed: missingLink || _opening ? null : _openStore,
                        icon: _opening
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.open_in_new_rounded),
                        label: Text(
                          _opening ? 'Opening app store…' : 'Update MyShop',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
