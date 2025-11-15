import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import '../../providers/auth_provider.dart';
import '../../services/local_storage.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _notifEmail = false;
  bool _notifPush = false;
  String? _avatarPath;

  @override
  void initState() {
    super.initState();
    final box = Hive.box(LocalStorageService.settingsBox);
    _notifEmail = box.get('notif_email', defaultValue: true) as bool;
    _notifPush = box.get('notif_push', defaultValue: true) as bool;
    _avatarPath = box.get('profile_image_path') as String?;
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile & Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE6E8EF)),
            ),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      radius: 34,
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.08),
                      backgroundImage:
                          (!kIsWeb &&
                              _avatarPath != null &&
                              _avatarPath!.isNotEmpty)
                          ? FileImage(File(_avatarPath!))
                          : null,
                      child:
                          (kIsWeb ||
                              _avatarPath == null ||
                              _avatarPath!.isEmpty)
                          ? const Icon(Icons.person, size: 32)
                          : null,
                    ),
                    Positioned(
                      right: -4,
                      bottom: -4,
                      child: InkWell(
                        onTap: _showAvatarSheet,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.edit,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user != null 
                          ? user.displayName ?? user.email.split('@').first
                          : 'User',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        children: [
                          Chip(label: Text(_capitalize(user?.role ?? ''))),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1F0),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE6E8EF)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.do_not_disturb_on_total_silence,
                  color: Colors.redAccent,
                ),
                const SizedBox(width: 10),
                const Expanded(child: Text('You are currently offline')),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Offline',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ExpansionTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Account Settings'),
              children: [
                ListTile(
                  title: const Text('Change password'),
                  onTap: () => _changePassword(context),
                ),
                const ListTile(title: Text('Two-factor authentication')),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ExpansionTile(
              leading: const Icon(Icons.notifications_none),
              title: const Text('Notification Preferences'),
              children: [
                SwitchListTile(
                  title: const Text('Email alerts'),
                  value: _notifEmail,
                  onChanged: (v) {
                    setState(() => _notifEmail = v);
                    Hive.box(
                      LocalStorageService.settingsBox,
                    ).put('notif_email', v);
                  },
                ),
                SwitchListTile(
                  title: const Text('Push notifications'),
                  value: _notifPush,
                  onChanged: (v) {
                    setState(() => _notifPush = v);
                    Hive.box(
                      LocalStorageService.settingsBox,
                    ).put('notif_push', v);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ExpansionTile(
              leading: const Icon(Icons.help_outline),
              title: const Text('Help & Support'),
              children: [
                const ListTile(title: Text('FAQ')),
                ListTile(
                  title: const Text('Contact support'),
                  onTap: () => _showSupport(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => ref.read(authProvider.notifier).logout(),
              icon: const Icon(Icons.logout),
              label: const Text('Log Out'),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  Future<void> _changePassword(BuildContext context) async {
    final user = ref.read(authProvider).user;
    if (user == null) return;
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    String? err;
    await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (ctx, setState) {
          return AlertDialog(
            title: const Text('Change Password'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: oldCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Current password',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: newCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'New password'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: confirmCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirm new password',
                  ),
                ),
                if (err != null) ...[
                  const SizedBox(height: 8),
                  Text(err!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  try {
                    // Re-authenticate the user
                    final credential = fb.EmailAuthProvider.credential(
                      email: user.email,
                      password: oldCtrl.text,
                    );
                    
                    // Re-authenticate user
                    await fb.FirebaseAuth.instance.currentUser!
                        .reauthenticateWithCredential(credential);
                    
                    // Update password
                    if (newCtrl.text.isNotEmpty && 
                        newCtrl.text == confirmCtrl.text) {
                      await fb.FirebaseAuth.instance.currentUser!
                          .updatePassword(newCtrl.text);
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('Password updated successfully')),
                        );
                        Navigator.pop(ctx, true);
                      }
                    } else {
                      setState(() => err = 'Passwords do not match or are empty');
                    }
                  } on fb.FirebaseAuthException catch (e) {
                    setState(() => err = e.message ?? 'Failed to update password');
                  } catch (e) {
                    setState(() => err = 'An error occurred');
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showSupport(BuildContext context) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Contact Support'),
        content: const Text(
          'Email: support@parishkeeper.app\nWe aim to respond within 24 hours.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showAvatarSheet() {
    if (kIsWeb) {
      // Basic notice for web builds
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Image picking is not supported on web in this build.'),
        ),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () async {
                Navigator.pop(c);
                await _pickAvatar(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () async {
                Navigator.pop(c);
                await _pickAvatar(ImageSource.camera);
              },
            ),
            if (_avatarPath != null && _avatarPath!.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Remove photo'),
                onTap: () async {
                  Navigator.pop(c);
                  setState(() => _avatarPath = null);
                  Hive.box(
                    LocalStorageService.settingsBox,
                  ).delete('profile_image_path');
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAvatar(ImageSource source) async {
    final picker = ImagePicker();
    final x = await picker.pickImage(source: source, imageQuality: 85);
    if (x == null) return;
    if (!mounted) return;
    setState(() => _avatarPath = x.path);
    Hive.box(LocalStorageService.settingsBox).put('profile_image_path', x.path);
  }
}
