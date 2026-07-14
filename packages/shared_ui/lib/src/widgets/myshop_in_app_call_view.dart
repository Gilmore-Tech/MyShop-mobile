import 'package:flutter/material.dart';

import '../theme/myshop_colors.dart';
import '../theme/myshop_spacing.dart';

class MyShopInAppCallView extends StatelessWidget {
  const MyShopInAppCallView({
    super.key,
    required this.peerName,
    required this.statusLabel,
    required this.contextLabel,
    required this.isLoading,
    required this.isEnding,
    required this.muted,
    required this.speakerOn,
    required this.onToggleMuted,
    required this.onToggleSpeaker,
    required this.onEndCall,
    this.incomingRinging = false,
    this.isAccepting = false,
    this.isDeclining = false,
    this.onAcceptCall,
    this.onDeclineCall,
    this.errorMessage,
  });

  final String peerName;
  final String statusLabel;
  final String contextLabel;
  final bool isLoading;
  final bool isEnding;
  final bool muted;
  final bool speakerOn;
  final VoidCallback? onToggleMuted;
  final VoidCallback? onToggleSpeaker;
  final VoidCallback? onEndCall;
  final bool incomingRinging;
  final bool isAccepting;
  final bool isDeclining;
  final VoidCallback? onAcceptCall;
  final VoidCallback? onDeclineCall;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: MyShopColors.darkSlate,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: MyShopColors.textOnPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(MyShopSpacing.lg),
          child: Column(
            children: [
              const Spacer(),
              CircleAvatar(
                radius: 54,
                backgroundColor:
                    MyShopColors.primaryGold.withValues(alpha: 0.18),
                child: Text(
                  _initials(peerName),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: MyShopColors.textOnPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: MyShopSpacing.lg),
              Text(
                peerName,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: MyShopColors.textOnPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: MyShopSpacing.xs),
              Text(
                statusLabel,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: MyShopColors.textOnPrimary.withValues(alpha: 0.78),
                ),
              ),
              const SizedBox(height: MyShopSpacing.sm),
              Text(
                contextLabel,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: MyShopColors.textOnPrimary.withValues(alpha: 0.62),
                ),
              ),
              if (isLoading) ...[
                const SizedBox(height: MyShopSpacing.xl),
                const CircularProgressIndicator(
                  color: MyShopColors.primaryGold,
                ),
              ],
              if (errorMessage != null && errorMessage!.isNotEmpty) ...[
                const SizedBox(height: MyShopSpacing.lg),
                Text(
                  errorMessage!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: MyShopColors.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const Spacer(),
              if (isLoading)
                const SizedBox(height: 72)
              else if (incomingRinging)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _IncomingCallAction(
                      label: 'Decline',
                      icon: Icons.call_end_rounded,
                      backgroundColor: MyShopColors.error,
                      loading: isDeclining,
                      onPressed:
                          isAccepting || isDeclining ? null : onDeclineCall,
                    ),
                    _IncomingCallAction(
                      label: 'Accept',
                      icon: Icons.call_rounded,
                      backgroundColor: MyShopColors.success,
                      loading: isAccepting,
                      onPressed:
                          isAccepting || isDeclining ? null : onAcceptCall,
                    ),
                  ],
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _CallControl(
                      tooltip: muted ? 'Unmute' : 'Mute',
                      icon: muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                      active: muted,
                      onPressed: onToggleMuted,
                    ),
                    const SizedBox(width: MyShopSpacing.lg),
                    _EndCallButton(
                      isEnding: isEnding,
                      onPressed: onEndCall,
                    ),
                    const SizedBox(width: MyShopSpacing.lg),
                    _CallControl(
                      tooltip: speakerOn ? 'Speaker off' : 'Speaker',
                      icon: speakerOn
                          ? Icons.volume_up_rounded
                          : Icons.volume_down_rounded,
                      active: speakerOn,
                      onPressed: onToggleSpeaker,
                    ),
                  ],
                ),
              const SizedBox(height: MyShopSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }

  static String _initials(String value) {
    final parts = value.trim().split(RegExp(r'\s+'));
    final letters = parts
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part.substring(0, 1).toUpperCase())
        .join();
    return letters.isEmpty ? 'MS' : letters;
  }
}

class _IncomingCallAction extends StatelessWidget {
  const _IncomingCallAction({
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.loading,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color backgroundColor;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filled(
          onPressed: onPressed,
          style: IconButton.styleFrom(
            fixedSize: const Size.square(72),
            backgroundColor: backgroundColor,
            foregroundColor: MyShopColors.textOnPrimary,
            disabledBackgroundColor: backgroundColor.withValues(alpha: 0.55),
          ),
          icon: loading
              ? const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: MyShopColors.textOnPrimary,
                  ),
                )
              : Icon(icon, size: 32),
        ),
        const SizedBox(height: MyShopSpacing.xs),
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: MyShopColors.textOnPrimary,
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}

class _CallControl extends StatelessWidget {
  const _CallControl({
    required this.tooltip,
    required this.icon,
    required this.active,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final bool active;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton.filled(
        onPressed: onPressed,
        style: IconButton.styleFrom(
          fixedSize: const Size.square(58),
          backgroundColor: active
              ? MyShopColors.primaryGold
              : MyShopColors.textOnPrimary.withValues(alpha: 0.14),
          foregroundColor: MyShopColors.textOnPrimary,
        ),
        icon: Icon(icon),
      ),
    );
  }
}

class _EndCallButton extends StatelessWidget {
  const _EndCallButton({
    required this.isEnding,
    required this.onPressed,
  });

  final bool isEnding;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'End call',
      child: IconButton.filled(
        onPressed: isEnding ? null : onPressed,
        style: IconButton.styleFrom(
          fixedSize: const Size.square(68),
          backgroundColor: MyShopColors.error,
          foregroundColor: MyShopColors.textOnPrimary,
          disabledBackgroundColor: MyShopColors.error.withValues(alpha: 0.5),
          disabledForegroundColor:
              MyShopColors.textOnPrimary.withValues(alpha: 0.72),
        ),
        icon: isEnding
            ? const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: MyShopColors.textOnPrimary,
                ),
              )
            : const Icon(Icons.call_end_rounded),
      ),
    );
  }
}
