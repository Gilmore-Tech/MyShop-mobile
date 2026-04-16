import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/support_legal_provider.dart';

// ── Screen ────────────────────────────────────────────────────────────────────
// Contact Support  → in-app chat / WhatsApp support link
// Report an Issue  → TODO: POST /v1/support/issues
// Legal documents  → in-app WebView or external browser

class SupportLegalScreen extends ConsumerStatefulWidget {
  const SupportLegalScreen({super.key});

  @override
  ConsumerState<SupportLegalScreen> createState() =>
      _SupportLegalScreenState();
}

class _SupportLegalScreenState extends ConsumerState<SupportLegalScreen> {
  late final TextEditingController _searchCtrl;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size   = MediaQuery.sizeOf(context);
    final w      = size.width;
    final h      = size.height;
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      appBar: _buildAppBar(context, w),
      body: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: bottom + h * 0.032),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: h * 0.020),

            // ── Search ─────────────────────────────────────────────────────
            _SearchBar(ctrl: _searchCtrl, w: w, h: h, ref: ref),
            SizedBox(height: h * 0.009),
            _CommonlySearched(w: w, h: h),

            SizedBox(height: h * 0.026),

            // ── Direct Help ────────────────────────────────────────────────
            _SectionLabel(label: 'DIRECT HELP', w: w, h: h),
            _ContactSupportCard(w: w, h: h),
            SizedBox(height: h * 0.010),
            _ReportIssueCard(w: w, h: h),

            SizedBox(height: h * 0.028),

            // ── Browse Topics ──────────────────────────────────────────────
            _SectionLabelWithAction(
              label: 'BROWSE TOPICS',
              actionLabel: 'View All',
              onAction: () {/* TODO: navigate to full topics list */},
              w: w,
              h: h,
            ),
            _TopicsGrid(w: w, h: h),

            SizedBox(height: h * 0.028),

            // ── Legal & Policies ───────────────────────────────────────────
            _SectionLabel(label: 'LEGAL & POLICIES', w: w, h: h),
            _LegalSection(w: w, h: h),

            SizedBox(height: h * 0.040),

            // ── Footer ─────────────────────────────────────────────────────
            _Footer(w: w, h: h),
            SizedBox(height: h * 0.016),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, double w) {
    return AppBar(
      backgroundColor: MyShopColors.surfaceWhite,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: IconButton(
        icon: Icon(
          Icons.arrow_back,
          color: MyShopColors.textPrimary,
          size: w * 0.052,
        ),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      title: Text(
        'Support & Legal',
        style: TextStyle(
          fontFamily: 'Raleway',
          fontSize: w * 0.050,
          fontWeight: FontWeight.w700,
          color: MyShopColors.textPrimary,
          height: 1.3,
        ),
      ),
      centerTitle: false,
    );
  }
}

// ── Search bar ────────────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  final TextEditingController ctrl;
  final double w;
  final double h;
  final WidgetRef ref;
  const _SearchBar(
      {required this.ctrl, required this.w, required this.h, required this.ref});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.044),
      child: Container(
        height: h * 0.058,
        decoration: BoxDecoration(
          color: MyShopColors.surfaceWhite,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: MyShopColors.divider, width: 1),
          boxShadow: const [
            BoxShadow(
              color: Color(0x08000000),
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: TextField(
          controller: ctrl,
          onChanged: (v) =>
              ref.read(supportLegalProvider.notifier).updateSearch(v),
          style: TextStyle(
            fontFamily: 'Raleway',
            fontSize: w * 0.036,
            fontWeight: FontWeight.w400,
            color: MyShopColors.textPrimary,
            height: 1.3,
          ),
          decoration: InputDecoration(
            hintText: 'Search help articles...',
            hintStyle: TextStyle(
              fontFamily: 'Raleway',
              fontSize: w * 0.036,
              fontWeight: FontWeight.w400,
              color: MyShopColors.textHint,
              height: 1.3,
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              color: MyShopColors.textHint,
              size: w * 0.050,
            ),
            border: InputBorder.none,
            contentPadding:
                EdgeInsets.symmetric(vertical: h * 0.014),
          ),
        ),
      ),
    );
  }
}

// ── Commonly searched ─────────────────────────────────────────────────────────

class _CommonlySearched extends StatelessWidget {
  final double w;
  final double h;
  const _CommonlySearched({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.044),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: w * 0.010,
        children: [
          Text(
            'Commonly searched:',
            style: TextStyle(
              fontFamily: 'Raleway',
              fontSize: w * 0.030,
              fontWeight: FontWeight.w400,
              color: MyShopColors.textSecondary,
              height: 1.5,
            ),
          ),
          ...kCommonSearches.asMap().entries.map((entry) {
            final isLast = entry.key == kCommonSearches.length - 1;
            return Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: w * 0.010,
              children: [
                GestureDetector(
                  onTap: () {/* TODO: navigate to help article */},
                  child: Text(
                    entry.value,
                    style: TextStyle(
                      fontFamily: 'Raleway',
                      fontSize: w * 0.030,
                      fontWeight: FontWeight.w600,
                      color: MyShopColors.primaryGold,
                      height: 1.5,
                    ),
                  ),
                ),
                if (!isLast)
                  Text(
                    '·',
                    style: TextStyle(
                      fontSize: w * 0.030,
                      color: MyShopColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  final double w;
  final double h;
  const _SectionLabel(
      {required this.label, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: w * 0.044, right: w * 0.044, bottom: h * 0.010),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Raleway',
          fontSize: w * 0.026,
          fontWeight: FontWeight.w900,
          color: MyShopColors.textSecondary,
          letterSpacing: 1.4,
          height: 1.4,
        ),
      ),
    );
  }
}

// ── Section label with action ─────────────────────────────────────────────────

class _SectionLabelWithAction extends StatelessWidget {
  final String label;
  final String actionLabel;
  final VoidCallback onAction;
  final double w;
  final double h;
  const _SectionLabelWithAction({
    required this.label,
    required this.actionLabel,
    required this.onAction,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: w * 0.044, right: w * 0.044, bottom: h * 0.010),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Raleway',
              fontSize: w * 0.026,
              fontWeight: FontWeight.w900,
              color: MyShopColors.textSecondary,
              letterSpacing: 1.4,
              height: 1.4,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onAction,
            child: Text(
              actionLabel,
              style: TextStyle(
                fontFamily: 'Raleway',
                fontSize: w * 0.034,
                fontWeight: FontWeight.w700,
                color: MyShopColors.primaryGold,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Contact Support card ──────────────────────────────────────────────────────

class _ContactSupportCard extends StatelessWidget {
  final double w;
  final double h;
  const _ContactSupportCard({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.044),
      child: _DirectHelpCard(
        iconBg: MyShopColors.primaryGoldLight,
        icon: Icons.headset_mic_outlined,
        iconColor: MyShopColors.primaryGold,
        title: 'Contact Support',
        subtitle: 'Typical response time: < 10 mins',
        onTap: () {/* TODO: open in-app support chat */},
        w: w,
        h: h,
      ),
    );
  }
}

// ── Report Issue card ─────────────────────────────────────────────────────────

class _ReportIssueCard extends StatelessWidget {
  final double w;
  final double h;
  const _ReportIssueCard({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.044),
      child: _DirectHelpCard(
        iconBg: MyShopColors.darkSlate,
        icon: Icons.flag_outlined,
        iconColor: Colors.white,
        title: 'Report an Issue',
        subtitle: "Let us know if something isn't working",
        onTap: () {/* TODO: navigate to report issue form */},
        w: w,
        h: h,
      ),
    );
  }
}

class _DirectHelpCard extends StatelessWidget {
  final Color    iconBg;
  final IconData icon;
  final Color    iconColor;
  final String   title;
  final String   subtitle;
  final VoidCallback onTap;
  final double w;
  final double h;
  const _DirectHelpCard({
    required this.iconBg,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MyShopColors.surfaceWhite,
      borderRadius: BorderRadius.circular(12),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: MyShopColors.divider, width: 1),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: w * 0.041,
            vertical: h * 0.018,
          ),
          child: Row(
            children: [
              Container(
                width: w * 0.108,
                height: w * 0.108,
                decoration: BoxDecoration(
                  color: iconBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: w * 0.054),
              ),
              SizedBox(width: w * 0.034),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: 'Raleway',
                        fontSize: w * 0.040,
                        fontWeight: FontWeight.w700,
                        color: MyShopColors.textPrimary,
                        height: 1.3,
                      ),
                    ),
                    SizedBox(height: h * 0.004),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontFamily: 'Raleway',
                        fontSize: w * 0.031,
                        fontWeight: FontWeight.w400,
                        color: MyShopColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: w * 0.020),
              Icon(
                Icons.chevron_right_rounded,
                color: MyShopColors.textHint,
                size: w * 0.052,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Browse Topics grid ────────────────────────────────────────────────────────

class _TopicsGrid extends StatelessWidget {
  final double w;
  final double h;
  const _TopicsGrid({required this.w, required this.h});

  static const _topicIcons = <String, IconData>{
    'account_access':    Icons.person_outline_rounded,
    'payments_billing':  Icons.credit_card_outlined,
    'privacy_safety':    Icons.shield_outlined,
    'fraud_prevention':  Icons.gpp_good_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final gap = w * 0.030;
    final cardW = (w - w * 0.044 * 2 - gap) / 2;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.044),
      child: Column(
        children: [
          Row(
            children: [
              _TopicCard(
                topic: kHelpTopics[0],
                icon: _topicIcons[kHelpTopics[0].id]!,
                cardW: cardW,
                h: h,
                w: w,
              ),
              SizedBox(width: gap),
              _TopicCard(
                topic: kHelpTopics[1],
                icon: _topicIcons[kHelpTopics[1].id]!,
                cardW: cardW,
                h: h,
                w: w,
              ),
            ],
          ),
          SizedBox(height: gap),
          Row(
            children: [
              _TopicCard(
                topic: kHelpTopics[2],
                icon: _topicIcons[kHelpTopics[2].id]!,
                cardW: cardW,
                h: h,
                w: w,
              ),
              SizedBox(width: gap),
              _TopicCard(
                topic: kHelpTopics[3],
                icon: _topicIcons[kHelpTopics[3].id]!,
                cardW: cardW,
                h: h,
                w: w,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TopicCard extends StatelessWidget {
  final HelpTopic topic;
  final IconData  icon;
  final double    cardW;
  final double    w;
  final double    h;
  const _TopicCard({
    required this.topic,
    required this.icon,
    required this.cardW,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: cardW,
      child: Material(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () {/* TODO: navigate to topic article list */},
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: MyShopColors.divider, width: 1),
            ),
            padding: EdgeInsets.symmetric(
              horizontal: w * 0.034,
              vertical: h * 0.020,
            ),
            child: Row(
              children: [
                Container(
                  width: w * 0.086,
                  height: w * 0.086,
                  decoration: const BoxDecoration(
                    color: MyShopColors.surfaceGrey,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: MyShopColors.textSecondary, size: w * 0.042),
                ),
                SizedBox(width: w * 0.022),
                Expanded(
                  child: Text(
                    topic.title,
                    style: TextStyle(
                      fontFamily: 'Raleway',
                      fontSize: w * 0.033,
                      fontWeight: FontWeight.w600,
                      color: MyShopColors.textPrimary,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Legal & Policies section ──────────────────────────────────────────────────

class _LegalSection extends StatelessWidget {
  final double w;
  final double h;
  const _LegalSection({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: w * 0.044),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: kLegalItems.asMap().entries.map((entry) {
          final idx  = entry.key;
          final item = entry.value;
          final isFirst = idx == 0;
          final isLast  = idx == kLegalItems.length - 1;

          return Column(
            children: [
              _LegalRow(
                item: item,
                isFirst: isFirst,
                isLast: isLast,
                w: w,
                h: h,
              ),
              if (!isLast)
                Padding(
                  padding: EdgeInsets.only(left: w * 0.044),
                  child: const Divider(
                      color: MyShopColors.divider, height: 1, thickness: 1),
                ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _LegalRow extends StatelessWidget {
  final LegalItem item;
  final bool  isFirst;
  final bool  isLast;
  final double w;
  final double h;
  const _LegalRow({
    required this.item,
    required this.isFirst,
    required this.isLast,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {/* TODO: navigate to legal document */},
      borderRadius: BorderRadius.vertical(
        top:    isFirst ? const Radius.circular(12) : Radius.zero,
        bottom: isLast  ? const Radius.circular(12) : Radius.zero,
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: w * 0.044,
          vertical: h * 0.018,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                item.title,
                style: TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: w * 0.038,
                  fontWeight: FontWeight.w500,
                  color: MyShopColors.textPrimary,
                  height: 1.3,
                ),
              ),
            ),
            Icon(
              item.isExternal
                  ? Icons.open_in_new_rounded
                  : Icons.chevron_right_rounded,
              color: MyShopColors.textHint,
              size: item.isExternal ? w * 0.042 : w * 0.052,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Footer ────────────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  final double w;
  final double h;
  const _Footer({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Center(
          child: Text(
            'APP VERSION 4.1.2.0 (Build 2024.05)',
            style: TextStyle(
              fontFamily: 'Raleway',
              fontSize: w * 0.028,
              fontWeight: FontWeight.w600,
              color: MyShopColors.textHint,
              letterSpacing: 0.4,
              height: 1.5,
            ),
          ),
        ),
        SizedBox(height: h * 0.004),
        Center(
          child: Text(
            '© 2024 Client Mobile App. All rights reserved.',
            style: TextStyle(
              fontFamily: 'Raleway',
              fontSize: w * 0.027,
              fontWeight: FontWeight.w400,
              color: MyShopColors.textHint,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}
