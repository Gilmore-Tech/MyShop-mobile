import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart';

import '../../theme/myshop_colors.dart';
import '../../theme/myshop_spacing.dart';
import '../../theme/myshop_typography.dart';
import '../myshop_primary_button.dart';
import '../myshop_text_field.dart';
import '../myshop_toast.dart';
import '../../utils/media_picker_helper.dart';

/// Form for filing a new support ticket.
///
/// Caller hands us the [audience] (drives category dropdown filter), an
/// optional [preselectedCategory], and an [onSubmit] that takes the
/// validated request + the local file paths chosen by the user. The
/// caller's provider is responsible for uploading attachments + calling
/// the support service — keeping this widget Riverpod-free.
class MyShopNewTicketScreen extends StatefulWidget {
  const MyShopNewTicketScreen({
    super.key,
    required this.audience,
    required this.onSubmit,
    this.preselectedCategory,
    this.referenceType,
    this.referenceId,
    this.attachmentsEnabled = false,
  });

  final SupportAudience audience;
  final TicketCategory? preselectedCategory;

  /// Optional pointer to a related ride / job / payout the user is
  /// filing about. Forwarded straight into [CreateTicketRequest] so the
  /// agent console can surface the underlying record.
  final String? referenceType;
  final String? referenceId;

  /// BR-61 release containment. Keep false until the private attachment read,
  /// retention and cleanup contract has passed release evidence.
  final bool attachmentsEnabled;

  /// Fired when the user taps Submit and validation passes. Returns
  /// `true` to dismiss the screen, `false` to keep it open (e.g. to let
  /// the user retry after a backend error).
  final Future<bool> Function({
    required TicketCategory category,
    required String subject,
    required String description,
    required List<File> attachments,
  }) onSubmit;

  @override
  State<MyShopNewTicketScreen> createState() => _MyShopNewTicketScreenState();
}

class _MyShopNewTicketScreenState extends State<MyShopNewTicketScreen> {
  final _subjectCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  late TicketCategory _category;
  final List<File> _attachments = [];
  bool _submitting = false;

  static const _maxSubjectLength = 120;
  static const _maxDescriptionLength = 4000;
  static const _maxAttachments = 4;

  List<TicketCategory> get _categoryOptions =>
      widget.audience == SupportAudience.client
          ? TicketCategory.clientCategories
          : TicketCategory.providerCategories;

  @override
  void initState() {
    super.initState();
    _category = widget.preselectedCategory ?? _categoryOptions.first;
  }

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  Future<void> _addAttachment() async {
    if (_attachments.length >= _maxAttachments) {
      MyShopToast.show(
        context,
        message: 'You can attach up to $_maxAttachments files.',
      );
      return;
    }
    final picked = await MediaPickerHelper.pickAttachment(context);
    if (picked == null) return;
    setState(() => _attachments.add(picked));
  }

  Future<void> _submit() async {
    final subject = _subjectCtrl.text.trim();
    final description = _descriptionCtrl.text.trim();

    if (subject.isEmpty) {
      MyShopToast.show(context, message: 'Add a short subject.');
      return;
    }
    if (subject.length > _maxSubjectLength) {
      MyShopToast.show(
        context,
        message: 'Subject is too long (max $_maxSubjectLength chars).',
      );
      return;
    }
    if (description.isEmpty) {
      MyShopToast.show(
        context,
        message: 'Describe the issue so we can help.',
      );
      return;
    }
    if (description.length > _maxDescriptionLength) {
      MyShopToast.show(
        context,
        message: 'Description is too long (max $_maxDescriptionLength chars).',
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final dismissed = await widget.onSubmit(
        category: _category,
        subject: subject,
        description: description,
        attachments: widget.attachmentsEnabled
            ? List.unmodifiable(_attachments)
            : const <File>[],
      );
      if (dismissed && mounted) Navigator.of(context).maybePop();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      appBar: AppBar(
        backgroundColor: MyShopColors.surfaceWhite,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back,
            color: MyShopColors.textPrimary,
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'New ticket',
          style: MyShopTypography.h1.copyWith(fontSize: 18),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(MyShopSpacing.md),
                children: [
                  Text(
                    'CATEGORY',
                    style: MyShopTypography.overline.copyWith(
                      color: MyShopColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: MyShopSpacing.sm),
                  _CategoryDropdown(
                    value: _category,
                    options: _categoryOptions,
                    onChanged: (c) => setState(() => _category = c),
                  ),
                  const SizedBox(height: MyShopSpacing.lg),
                  Text(
                    'SUBJECT',
                    style: MyShopTypography.overline.copyWith(
                      color: MyShopColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: MyShopSpacing.sm),
                  MyShopTextField(
                    controller: _subjectCtrl,
                    hint: 'Short summary of the issue',
                    maxLength: _maxSubjectLength,
                  ),
                  const SizedBox(height: MyShopSpacing.lg),
                  Text(
                    'DESCRIPTION',
                    style: MyShopTypography.overline.copyWith(
                      color: MyShopColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: MyShopSpacing.sm),
                  Container(
                    decoration: BoxDecoration(
                      color: MyShopColors.surfaceWhite,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: MyShopColors.divider),
                    ),
                    child: TextField(
                      controller: _descriptionCtrl,
                      maxLines: 6,
                      maxLength: _maxDescriptionLength,
                      style: MyShopTypography.body1.copyWith(
                        color: MyShopColors.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText:
                            'Tell us what happened, when, and what you expected.',
                        hintStyle: MyShopTypography.body1.copyWith(
                          color: MyShopColors.textHint,
                          fontWeight: FontWeight.w400,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.all(MyShopSpacing.md),
                        counterStyle: MyShopTypography.caption,
                      ),
                    ),
                  ),
                  const SizedBox(height: MyShopSpacing.lg),
                  if (widget.attachmentsEnabled) ...[
                    Row(
                      children: [
                        Text(
                          'ATTACHMENTS',
                          style: MyShopTypography.overline.copyWith(
                            color: MyShopColors.textSecondary,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${_attachments.length}/$_maxAttachments',
                          style: MyShopTypography.caption,
                        ),
                      ],
                    ),
                    const SizedBox(height: MyShopSpacing.sm),
                    _AttachmentsRow(
                      files: _attachments,
                      onAdd: _addAttachment,
                      onRemove: (i) => setState(() => _attachments.removeAt(i)),
                      maxAttachments: _maxAttachments,
                    ),
                  ] else
                    Container(
                      key:
                          const ValueKey('support-attachments-disabled-notice'),
                      padding: const EdgeInsets.all(MyShopSpacing.md),
                      decoration: BoxDecoration(
                        color: MyShopColors.surfaceWhite,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: MyShopColors.divider),
                      ),
                      child: Text(
                        'Attachments are temporarily unavailable. Describe the issue here and you can still submit your ticket.',
                        style: MyShopTypography.body2.copyWith(
                          color: MyShopColors.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(
                MyShopSpacing.md,
                MyShopSpacing.sm,
                MyShopSpacing.md,
                MyShopSpacing.md,
              ),
              decoration: const BoxDecoration(
                color: MyShopColors.surfaceWhite,
                border: Border(top: BorderSide(color: MyShopColors.divider)),
              ),
              child: MyShopPrimaryButton(
                label: _submitting ? 'Submitting…' : 'Submit ticket',
                onPressed: _submitting ? null : _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryDropdown extends StatelessWidget {
  const _CategoryDropdown({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final TicketCategory value;
  final List<TicketCategory> options;
  final ValueChanged<TicketCategory> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<TicketCategory>(
          value: value,
          isExpanded: true,
          icon: const Icon(
            Icons.keyboard_arrow_down,
            color: MyShopColors.textSecondary,
          ),
          items: options
              .map(
                (c) => DropdownMenuItem(
                  value: c,
                  child: Text(_label(c), style: MyShopTypography.body1),
                ),
              )
              .toList(),
          onChanged: (c) {
            if (c != null) onChanged(c);
          },
        ),
      ),
    );
  }

  static String _label(TicketCategory c) {
    switch (c) {
      case TicketCategory.account:
        return 'Account';
      case TicketCategory.payments:
        return 'Payments';
      case TicketCategory.rides:
        return 'Rides';
      case TicketCategory.jobs:
        return 'Jobs';
      case TicketCategory.payouts:
        return 'Payouts';
      case TicketCategory.verification:
        return 'Verification';
      case TicketCategory.safety:
        return 'Safety';
      case TicketCategory.bug:
        return 'Bug / Something broken';
      case TicketCategory.other:
        return 'Other';
    }
  }
}

class _AttachmentsRow extends StatelessWidget {
  const _AttachmentsRow({
    required this.files,
    required this.onAdd,
    required this.onRemove,
    required this.maxAttachments,
  });

  final List<File> files;
  final VoidCallback onAdd;
  final void Function(int index) onRemove;
  final int maxAttachments;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: MyShopSpacing.sm,
      runSpacing: MyShopSpacing.sm,
      children: [
        for (var i = 0; i < files.length; i++)
          _AttachmentTile(
            file: files[i],
            onRemove: () => onRemove(i),
          ),
        if (files.length < maxAttachments)
          InkWell(
            onTap: onAdd,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: MyShopColors.surfaceWhite,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: MyShopColors.divider,
                  style: BorderStyle.solid,
                ),
              ),
              child: const Icon(
                Icons.add,
                color: MyShopColors.textSecondary,
              ),
            ),
          ),
      ],
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({required this.file, required this.onRemove});

  final File file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final isImage = _looksLikeImage(file.path);
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 72,
            height: 72,
            color: MyShopColors.surfaceGrey,
            child: isImage
                ? Image.file(file, fit: BoxFit.cover)
                : const Icon(
                    Icons.insert_drive_file_outlined,
                    color: MyShopColors.textSecondary,
                  ),
          ),
        ),
        Positioned(
          top: -4,
          right: -4,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(
                color: MyShopColors.darkSlate,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close,
                size: 14,
                color: MyShopColors.textOnDarkSlate,
              ),
            ),
          ),
        ),
      ],
    );
  }

  static bool _looksLikeImage(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp');
  }
}
