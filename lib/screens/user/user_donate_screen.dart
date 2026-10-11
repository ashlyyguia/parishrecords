import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../widgets/give_in_person_guide.dart';

class UserDonateScreen extends StatelessWidget {
  const UserDonateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('How to Donate'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: const GiveInPersonGuide(),
          ),
        ),
      ),
    );
  }
}
