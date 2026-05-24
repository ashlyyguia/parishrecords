import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../widgets/online_donation_flow.dart';

class UserDonateScreen extends StatelessWidget {
  const UserDonateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Online Donation'),
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
            child: OnlineDonationFlow(
              visualStyle: OnlineDonationVisualStyle.app,
              prefillName: user?.displayName,
              prefillEmail: user?.email,
              onCompleted: () {
                if (context.canPop()) context.pop(true);
              },
            ),
          ),
        ),
      ),
    );
  }
}
