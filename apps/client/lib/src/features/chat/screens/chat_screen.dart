import 'package:flutter/material.dart';

/// In-app chat with provider during active ride/job. Auto-closes on completion
/// PRD Reference: PRD 4.7
class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ChatScreen')),
      body: const Center(
        child: Text('TODO: Implement ChatScreen'),
      ),
    );
  }
}
