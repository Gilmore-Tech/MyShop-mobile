import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// ── Design tokens ──────────────────────────────────────────────────────────────
const _bg            = Color(0xFFF6F7F8);
const _surfaceWhite  = Color(0xFFFFFFFF);
const _surfaceGrey   = Color(0xFFF3F5F6);
const _textPrimary   = Color(0xFF161A1D);
const _textSecondary = Color(0xFF555E68);
const _gold          = Color(0xFFF5A623);
const _darkSlate     = Color(0xFF46535D);
const _divider       = Color(0xFFE8EAEC);

// ── Model ──────────────────────────────────────────────────────────────────────

class _Message {
  final String  id;
  final String  text;
  final bool    fromMe;
  final String  time;

  const _Message({
    required this.id,
    required this.text,
    required this.fromMe,
    required this.time,
  });
}

// ── Provider ───────────────────────────────────────────────────────────────────
// PRD § 4.7 — In-app chat during active ride or job.
// EDD: WS /v1/chat/:bookingId  — events: message, typing, read

class _ChatNotifier extends StateNotifier<List<_Message>> {
  _ChatNotifier() : super(const [
    _Message(
        id: '1', text: 'Hello! I\'m on my way.',
        fromMe: false, time: '09:14 AM'),
    _Message(
        id: '2', text: 'Great, I\'m at the main gate.',
        fromMe: true, time: '09:15 AM'),
    _Message(
        id: '3', text: 'Okay, about 5 minutes.',
        fromMe: false, time: '09:15 AM'),
  ]);

  void send(String text) {
    if (text.trim().isEmpty) return;
    final now = TimeOfDay.now();
    final h = now.hourOfPeriod == 0 ? 12 : now.hourOfPeriod;
    final m = now.minute.toString().padLeft(2, '0');
    final period = now.period == DayPeriod.am ? 'AM' : 'PM';
    state = [
      ...state,
      _Message(
        id:     DateTime.now().millisecondsSinceEpoch.toString(),
        text:   text.trim(),
        fromMe: true,
        time:   '$h:$m $period',
      ),
    ];
    // TODO: WS send { type: "message", text }
  }
}

final _chatProvider = StateNotifierProvider.autoDispose<
    _ChatNotifier, List<_Message>>((_) => _ChatNotifier());

// ── Screen ─────────────────────────────────────────────────────────────────────

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller  = TextEditingController();
  final _scrollCtrl  = ScrollController();
  bool  _hasText     = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _send() {
    ref.read(_chatProvider.notifier).send(_controller.text);
    _controller.clear();
    setState(() => _hasText = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final size     = MediaQuery.sizeOf(context);
    final w        = size.width;
    final h        = size.height;
    final bot      = MediaQuery.paddingOf(context).bottom;
    final kb       = MediaQuery.viewInsetsOf(context).bottom;
    final messages = ref.watch(_chatProvider);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surfaceWhite,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: _textPrimary),
          onPressed: () => context.pop(),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              width:  w * 0.10,
              height: w * 0.10,
              decoration: const BoxDecoration(
                  color: _darkSlate, shape: BoxShape.circle),
              child: Icon(Icons.person_rounded,
                  color: Colors.white, size: w * 0.050),
            ),
            SizedBox(width: w * 0.024),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Kwame Asante',
                    style: TextStyle(
                      color:      _textPrimary,
                      fontSize:   w * 0.040,
                      fontWeight: FontWeight.w700,
                    )),
                Row(
                  children: [
                    Container(
                      width:  6,
                      height: 6,
                      decoration: const BoxDecoration(
                          color: Color(0xFF27AE60),
                          shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 4),
                    Text('Online',
                        style: TextStyle(
                            color:    const Color(0xFF27AE60),
                            fontSize: w * 0.028)),
                  ],
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.phone_rounded, color: _textPrimary),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          // Messages
          Expanded(
            child: ListView.builder(
              controller:  _scrollCtrl,
              padding:     EdgeInsets.symmetric(
                  horizontal: w * 0.04, vertical: h * 0.016),
              itemCount:   messages.length,
              itemBuilder: (_, i) => _Bubble(
                  msg: messages[i], w: w, h: h),
            ),
          ),
          // Masked-phone notice
          Container(
            color:   _surfaceGrey,
            padding: EdgeInsets.symmetric(
                horizontal: w * 0.05, vertical: h * 0.010),
            child: Row(
              children: [
                const Icon(Icons.security_rounded,
                    color: _textSecondary, size: 14),
                SizedBox(width: w * 0.016),
                Expanded(
                  child: Text(
                    'Phone numbers are masked. Use this chat to communicate.',
                    style: TextStyle(
                        color:    _textSecondary,
                        fontSize: w * 0.028),
                  ),
                ),
              ],
            ),
          ),
          // Input bar
          Container(
            color:   _surfaceWhite,
            padding: EdgeInsets.fromLTRB(
                w * 0.04, h * 0.012, w * 0.04,
                (kb > 0 ? kb : bot) + h * 0.016),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Container(
                    constraints: BoxConstraints(maxHeight: h * 0.14),
                    decoration: BoxDecoration(
                      color:        _surfaceGrey,
                      borderRadius: BorderRadius.circular(22),
                      border:       Border.all(color: _divider),
                    ),
                    child: TextField(
                      controller: _controller,
                      maxLines:   null,
                      onChanged:  (v) =>
                          setState(() => _hasText = v.trim().isNotEmpty),
                      style: TextStyle(
                          color: _textPrimary, fontSize: w * 0.036),
                      decoration: InputDecoration(
                        hintText: 'Message…',
                        hintStyle: TextStyle(
                            color:    _textSecondary.withAlpha(120),
                            fontSize: w * 0.034),
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: w * 0.040,
                            vertical:   h * 0.014),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: w * 0.024),
                AnimatedScale(
                  scale:    _hasText ? 1.0 : 0.85,
                  duration: const Duration(milliseconds: 180),
                  child: GestureDetector(
                    onTap: _hasText ? _send : null,
                    child: Container(
                      width:  w * 0.118,
                      height: w * 0.118,
                      decoration: BoxDecoration(
                        color:  _hasText ? _gold : _surfaceGrey,
                        shape:  BoxShape.circle,
                      ),
                      child: Icon(Icons.send_rounded,
                          color: _hasText
                              ? Colors.white
                              : _textSecondary,
                          size: w * 0.050),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Chat bubble ────────────────────────────────────────────────────────────────

class _Bubble extends StatelessWidget {
  final _Message msg;
  final double   w, h;
  const _Bubble({required this.msg, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    final fromMe = msg.fromMe;
    return Padding(
      padding: EdgeInsets.only(bottom: h * 0.012),
      child: Row(
        mainAxisAlignment:
            fromMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!fromMe) ...[
            Container(
              width:  w * 0.08,
              height: w * 0.08,
              decoration: const BoxDecoration(
                  color: _darkSlate, shape: BoxShape.circle),
              child: Icon(Icons.person_rounded,
                  color: Colors.white, size: w * 0.040),
            ),
            SizedBox(width: w * 0.020),
          ],
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: w * 0.65),
            child: Container(
              padding: EdgeInsets.symmetric(
                  horizontal: w * 0.040, vertical: h * 0.012),
              decoration: BoxDecoration(
                color: fromMe ? _gold : _surfaceWhite,
                borderRadius: BorderRadius.only(
                  topLeft:     const Radius.circular(16),
                  topRight:    const Radius.circular(16),
                  bottomLeft:  Radius.circular(fromMe ? 16 : 4),
                  bottomRight: Radius.circular(fromMe ? 4 : 16),
                ),
                boxShadow: [
                  BoxShadow(
                      color:      Colors.black.withAlpha(8),
                      blurRadius: 4,
                      offset:     const Offset(0, 2)),
                ],
              ),
              child: Column(
                crossAxisAlignment: fromMe
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Text(msg.text,
                      style: TextStyle(
                        color:    fromMe ? Colors.white : _textPrimary,
                        fontSize: w * 0.036,
                        height:   1.4,
                      )),
                  const SizedBox(height: 4),
                  Text(msg.time,
                      style: TextStyle(
                        color: fromMe
                            ? Colors.white.withAlpha(180)
                            : _textSecondary,
                        fontSize: w * 0.024,
                      )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
