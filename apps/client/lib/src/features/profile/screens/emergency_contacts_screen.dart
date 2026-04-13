import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// ── Design tokens ──────────────────────────────────────────────────────────────
const _bg            = Color(0xFFF6F7F8);
const _surfaceWhite  = Color(0xFFFFFFFF);
const _surfaceGrey   = Color(0xFFF3F5F6);
const _textPrimary   = Color(0xFF161A1D);
const _textSecondary = Color(0xFF555E68);
const _gold          = Color(0xFFF5A623);
const _danger        = Color(0xFFEB5757);
const _dangerLight   = Color(0xFFFDE8E8);
const _divider       = Color(0xFFE8EAEC);

// ── Model ──────────────────────────────────────────────────────────────────────

class _Contact {
  final String id;
  final String name;
  final String phone;
  final String relation;

  const _Contact({
    required this.id,
    required this.name,
    required this.phone,
    required this.relation,
  });
}

// ── Provider ───────────────────────────────────────────────────────────────────
// EDD: GET /v1/users/me/emergency-contacts
//      PUT /v1/users/me/emergency-contacts  { contacts: [...] }

class _ContactsNotifier extends StateNotifier<List<_Contact>> {
  _ContactsNotifier() : super(const [
    _Contact(
        id: '1', name: 'Akosua Mensah',
        phone: '+233 24 555 0101', relation: 'Wife'),
    _Contact(
        id: '2', name: 'Kweku Boateng',
        phone: '+233 27 333 0202', relation: 'Brother'),
  ]);

  void add(_Contact c) => state = [...state, c];

  void remove(String id) =>
      state = state.where((c) => c.id != id).toList();
}

final _contactsProvider = StateNotifierProvider.autoDispose<
    _ContactsNotifier, List<_Contact>>((_) => _ContactsNotifier());

// ── Screen ─────────────────────────────────────────────────────────────────────

class EmergencyContactsScreen extends ConsumerWidget {
  const EmergencyContactsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size     = MediaQuery.sizeOf(context);
    final w        = size.width;
    final h        = size.height;
    final contacts = ref.watch(_contactsProvider);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surfaceWhite,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: _textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text('Emergency Contacts',
            style: TextStyle(
                color:      _textPrimary,
                fontSize:   w * 0.044,
                fontWeight: FontWeight.w700)),
        centerTitle: false,
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: EdgeInsets.all(w * 0.05),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _InfoBanner(w: w),
                SizedBox(height: h * 0.024),
                if (contacts.isEmpty)
                  _EmptyState(w: w, h: h)
                else
                  _ContactsList(
                      contacts: contacts,
                      onRemove: (id) =>
                          ref.read(_contactsProvider.notifier).remove(id),
                      w: w, h: h),
                SizedBox(height: h * 0.024),
                if (contacts.length < 3)
                  SizedBox(
                    width:  double.infinity,
                    height: h * 0.062,
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          _showAddSheet(context, ref, w),
                      icon:  const Icon(Icons.person_add_alt_1_rounded),
                      label: const Text('Add Emergency Contact'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _gold,
                        side:  const BorderSide(color: _gold),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                SizedBox(height: h * 0.016),
                _LimitNote(count: contacts.length, w: w),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddSheet(BuildContext ctx, WidgetRef ref, double w) {
    showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddContactSheet(
        w: w,
        onSave: (c) => ref.read(_contactsProvider.notifier).add(c),
      ),
    );
  }
}

// ── Info banner ────────────────────────────────────────────────────────────────

class _InfoBanner extends StatelessWidget {
  final double w;
  const _InfoBanner({required this.w});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(w * 0.04),
      decoration: BoxDecoration(
        color:        _dangerLight,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: _danger.withAlpha(60)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.emergency_rounded, color: _danger, size: 20),
          SizedBox(width: w * 0.030),
          Expanded(
            child: Text(
              'Emergency contacts are notified when you trigger an SOS alert. '
              'They receive your real-time location link.',
              style: TextStyle(
                  color:  _danger,
                  fontSize: w * 0.033,
                  height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Contacts list ──────────────────────────────────────────────────────────────

class _ContactsList extends StatelessWidget {
  final List<_Contact> contacts;
  final void Function(String) onRemove;
  final double w, h;

  const _ContactsList({
    required this.contacts,
    required this.onRemove,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color:        _surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: _divider),
      ),
      child: Column(
        children: contacts.map((c) {
          final isLast = c == contacts.last;
          return Column(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: w * 0.04, vertical: h * 0.018),
                child: Row(
                  children: [
                    Container(
                      width:  w * 0.12,
                      height: w * 0.12,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFDE8E8),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.emergency_rounded,
                          color: _danger, size: w * 0.056),
                    ),
                    SizedBox(width: w * 0.030),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.name,
                              style: TextStyle(
                                color:      _textPrimary,
                                fontSize:   w * 0.038,
                                fontWeight: FontWeight.w700,
                              )),
                          const SizedBox(height: 2),
                          Text(c.phone,
                              style: TextStyle(
                                  color:    _textSecondary,
                                  fontSize: w * 0.032)),
                          const SizedBox(height: 2),
                          Text(c.relation,
                              style: TextStyle(
                                  color:    _textSecondary,
                                  fontSize: w * 0.028)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_outline_rounded,
                          color: _danger, size: w * 0.052),
                      onPressed: () => onRemove(c.id),
                    ),
                  ],
                ),
              ),
              if (!isLast)
                const Divider(
                    height: 1, indent: 16, endIndent: 16,
                    color: _divider),
            ],
          );
        }).toList(),
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final double w, h;
  const _EmptyState({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: h * 0.04),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.people_outline_rounded,
                color: _textSecondary.withAlpha(80),
                size: w * 0.16),
            SizedBox(height: h * 0.016),
            Text('No contacts added yet',
                style: TextStyle(
                    color: _textSecondary, fontSize: w * 0.036)),
          ],
        ),
      ),
    );
  }
}

// ── Limit note ─────────────────────────────────────────────────────────────────

class _LimitNote extends StatelessWidget {
  final int    count;
  final double w;
  const _LimitNote({required this.count, required this.w});

  @override
  Widget build(BuildContext context) {
    return Text(
      'You can add up to 3 emergency contacts. ($count / 3 added)',
      style: TextStyle(
          color:    _textSecondary,
          fontSize: w * 0.030),
    );
  }
}

// ── Add contact bottom sheet ───────────────────────────────────────────────────

class _AddContactSheet extends StatefulWidget {
  final double          w;
  final void Function(_Contact) onSave;

  const _AddContactSheet({required this.w, required this.onSave});

  @override
  State<_AddContactSheet> createState() => _AddContactSheetState();
}

class _AddContactSheetState extends State<_AddContactSheet> {
  final _nameCtrl     = TextEditingController();
  final _phoneCtrl    = TextEditingController();
  final _relationCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _relationCtrl.dispose();
    super.dispose();
  }

  bool get _valid =>
      _nameCtrl.text.trim().isNotEmpty &&
      _phoneCtrl.text.replaceAll(RegExp(r'\D'), '').length >= 9;

  void _save() {
    if (!_valid) return;
    widget.onSave(_Contact(
      id:       DateTime.now().millisecondsSinceEpoch.toString(),
      name:     _nameCtrl.text.trim(),
      phone:    _phoneCtrl.text.trim(),
      relation: _relationCtrl.text.trim().isEmpty
          ? 'Contact'
          : _relationCtrl.text.trim(),
    ));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final w   = widget.w;
    final h   = MediaQuery.sizeOf(context).height;
    final bot = MediaQuery.paddingOf(context).bottom;
    final kb  = MediaQuery.viewInsetsOf(context).bottom;

    return Container(
      decoration: const BoxDecoration(
        color:        _surfaceWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
          w * 0.05, h * 0.020, w * 0.05, bot + kb + h * 0.028),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: w * 0.10, height: 4,
              decoration: BoxDecoration(
                color:        _surfaceGrey,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          SizedBox(height: h * 0.020),
          Text('Add Emergency Contact',
              style: TextStyle(
                color:      _textPrimary,
                fontSize:   w * 0.044,
                fontWeight: FontWeight.w700,
              )),
          SizedBox(height: h * 0.020),
          _SheetField(
              controller: _nameCtrl,
              hint:       'Full name',
              icon:       Icons.person_outline_rounded,
              onChanged:  (_) => setState(() {}),
              w: w, h: h),
          SizedBox(height: h * 0.014),
          _SheetField(
              controller: _phoneCtrl,
              hint:       'Phone number',
              icon:       Icons.phone_outlined,
              keyboard:   TextInputType.phone,
              formatters: [FilteringTextInputFormatter.allow(
                  RegExp(r'[\d\s\+]'))],
              onChanged:  (_) => setState(() {}),
              w: w, h: h),
          SizedBox(height: h * 0.014),
          _SheetField(
              controller: _relationCtrl,
              hint:       'Relationship (optional)',
              icon:       Icons.people_outline_rounded,
              onChanged:  (_) => setState(() {}),
              w: w, h: h),
          SizedBox(height: h * 0.024),
          AnimatedOpacity(
            opacity:  _valid ? 1.0 : 0.45,
            duration: const Duration(milliseconds: 200),
            child: SizedBox(
              width:  double.infinity,
              height: h * 0.062,
              child: ElevatedButton(
                onPressed: _valid ? _save : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor:         _gold,
                  foregroundColor:         Colors.white,
                  disabledBackgroundColor: _gold.withAlpha(80),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: Text('Save Contact',
                    style: TextStyle(
                        fontSize:   w * 0.040,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetField extends StatelessWidget {
  final TextEditingController      controller;
  final String                     hint;
  final IconData                   icon;
  final TextInputType              keyboard;
  final List<TextInputFormatter>?  formatters;
  final ValueChanged<String>       onChanged;
  final double                     w, h;

  const _SheetField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.keyboard   = TextInputType.text,
    this.formatters,
    required this.onChanged,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: h * 0.064,
      decoration: BoxDecoration(
        color:        _surfaceGrey,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: _divider),
      ),
      child: Row(
        children: [
          SizedBox(width: w * 0.04),
          Icon(icon, color: _textSecondary, size: 20),
          SizedBox(width: w * 0.024),
          Expanded(
            child: TextField(
              controller:      controller,
              keyboardType:    keyboard,
              inputFormatters: formatters,
              onChanged:       onChanged,
              style: TextStyle(
                  color: _textPrimary, fontSize: w * 0.036),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(
                    color:    _textSecondary.withAlpha(120),
                    fontSize: w * 0.034),
                border:         InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
