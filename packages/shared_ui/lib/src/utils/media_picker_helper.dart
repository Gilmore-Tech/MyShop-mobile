import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/myshop_colors.dart';
import '../theme/myshop_typography.dart';

/// Result from a media pick operation.
class MediaPickResult {
  const MediaPickResult({required this.files});

  /// The picked files. Empty if the user cancelled.
  final List<File> files;

  bool get cancelled => files.isEmpty;
  File? get single => files.isEmpty ? null : files.first;
}

/// Centralized helper for picking images and files across the app.
///
/// Shows a branded bottom sheet letting the user choose between camera,
/// gallery, or file browser depending on the context.
class MediaPickerHelper {
  MediaPickerHelper._();

  static final _imagePicker = ImagePicker();

  // ─────────────────────────────────────────────────────────────────────────
  // Public API
  // ─────────────────────────────────────────────────────────────────────────

  /// Shows a bottom sheet with Camera and Gallery options.
  /// Returns the picked image [File], or `null` if cancelled.
  static Future<File?> pickImage(BuildContext context) async {
    final source = await _showImageSourceSheet(context);
    if (source == null) return null;
    return _pickFromSource(source);
  }

  /// Opens the camera directly and returns the captured image.
  static Future<File?> pickFromCamera() async {
    return _pickFromSource(ImageSource.camera);
  }

  /// Opens the gallery directly and returns the selected image.
  static Future<File?> pickFromGallery() async {
    return _pickFromSource(ImageSource.gallery);
  }

  /// Pick multiple images from gallery.
  static Future<List<File>> pickMultipleImages() async {
    final images = await _imagePicker.pickMultiImage(imageQuality: 80);
    return images.map((xf) => File(xf.path)).toList();
  }

  /// Pick a document file (PDF, DOC, images, etc.).
  /// Useful for uploading verification documents.
  static Future<File?> pickDocument(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx'],
    );
    if (result == null || result.files.isEmpty) return null;
    final path = result.files.single.path;
    return path != null ? File(path) : null;
  }

  /// Shows a bottom sheet with Camera, Gallery, and File options.
  /// Used in chat and bid screens where all three make sense.
  static Future<File?> pickAttachment(BuildContext context) async {
    final choice = await _showAttachmentSheet(context);
    if (choice == null) return null;

    switch (choice) {
      case _AttachmentChoice.camera:
        return _pickFromSource(ImageSource.camera);
      case _AttachmentChoice.gallery:
        return _pickFromSource(ImageSource.gallery);
      case _AttachmentChoice.file:
        return pickDocument(context);
    }
  }

  /// Shows a bottom sheet for document upload — Camera or File picker.
  /// Used in document verification and profile screens.
  static Future<File?> pickDocumentWithCamera(BuildContext context) async {
    final choice = await _showDocumentUploadSheet(context);
    if (choice == null) return null;

    switch (choice) {
      case _DocUploadChoice.camera:
        return _pickFromSource(ImageSource.camera);
      case _DocUploadChoice.file:
        return pickDocument(context);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Private helpers
  // ─────────────────────────────────────────────────────────────────────────

  static Future<File?> _pickFromSource(ImageSource source) async {
    final xFile = await _imagePicker.pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 1920,
      maxHeight: 1920,
    );
    return xFile != null ? File(xFile.path) : null;
  }

  /// Camera vs Gallery bottom sheet.
  static Future<ImageSource?> _showImageSourceSheet(BuildContext context) {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _PickerSheet(
        title: 'Select Image',
        options: [
          _PickerOption(
            icon: Icons.camera_alt_outlined,
            label: 'Camera',
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          _PickerOption(
            icon: Icons.photo_library_outlined,
            label: 'Gallery',
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
        ],
      ),
    );
  }

  /// Camera, Gallery, File bottom sheet.
  static Future<_AttachmentChoice?> _showAttachmentSheet(
    BuildContext context,
  ) {
    return showModalBottomSheet<_AttachmentChoice>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _PickerSheet(
        title: 'Attach',
        options: [
          _PickerOption(
            icon: Icons.camera_alt_outlined,
            label: 'Camera',
            onTap: () => Navigator.pop(context, _AttachmentChoice.camera),
          ),
          _PickerOption(
            icon: Icons.photo_library_outlined,
            label: 'Gallery',
            onTap: () => Navigator.pop(context, _AttachmentChoice.gallery),
          ),
          _PickerOption(
            icon: Icons.description_outlined,
            label: 'File',
            onTap: () => Navigator.pop(context, _AttachmentChoice.file),
          ),
        ],
      ),
    );
  }

  /// Camera or File bottom sheet (for documents).
  static Future<_DocUploadChoice?> _showDocumentUploadSheet(
    BuildContext context,
  ) {
    return showModalBottomSheet<_DocUploadChoice>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _PickerSheet(
        title: 'Upload Document',
        options: [
          _PickerOption(
            icon: Icons.camera_alt_outlined,
            label: 'Take Photo',
            onTap: () => Navigator.pop(context, _DocUploadChoice.camera),
          ),
          _PickerOption(
            icon: Icons.description_outlined,
            label: 'Choose File',
            onTap: () => Navigator.pop(context, _DocUploadChoice.file),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Choice enums
// ─────────────────────────────────────────────────────────────────────────────

enum _AttachmentChoice { camera, gallery, file }

enum _DocUploadChoice { camera, file }

// ─────────────────────────────────────────────────────────────────────────────
// Bottom sheet UI
// ─────────────────────────────────────────────────────────────────────────────

class _PickerOption {
  const _PickerOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

class _PickerSheet extends StatelessWidget {
  const _PickerSheet({required this.title, required this.options});

  final String title;
  final List<_PickerOption> options;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;

    return Container(
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(w * 0.051)),
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            w * 0.061,
            h * 0.019,
            w * 0.061,
            h * 0.029,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: w * 0.092,
                height: h * 0.005,
                decoration: BoxDecoration(
                  color: MyShopColors.disabled,
                  borderRadius: BorderRadius.circular(w * 0.005),
                ),
              ),
              SizedBox(height: h * 0.019),
              Text(
                title,
                style: MyShopTypography.h3.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: w * 0.046,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: h * 0.029),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: options
                    .map((opt) => Expanded(child: _OptionTile(option: opt)))
                    .toList(),
              ),
              SizedBox(height: h * 0.019),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({required this.option});

  final _PickerOption option;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;
    final iconBox = w * 0.143;

    return GestureDetector(
      onTap: option.onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: iconBox,
            height: iconBox,
            decoration: BoxDecoration(
              color: MyShopColors.primaryGoldLight,
              shape: BoxShape.circle,
              border: Border.all(
                color: MyShopColors.primaryGold.withValues(alpha: 0.3),
              ),
            ),
            child: Icon(
              option.icon,
              size: iconBox * 0.43,
              color: MyShopColors.primaryGold,
            ),
          ),
          SizedBox(height: h * 0.010),
          Text(
            option.label,
            style: MyShopTypography.body1.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: w * 0.033,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
