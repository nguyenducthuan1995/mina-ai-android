import 'package:flutter/material.dart';
import 'package:ai_assistant/screens/assistant_selection_screen.dart';

class DiscoveryScreen extends StatelessWidget {
  const DiscoveryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AssistantSelectionScreen(isModal: false);
  }
}
