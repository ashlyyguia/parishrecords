import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class RegisterWithInviteScreen extends StatefulWidget {
  const RegisterWithInviteScreen({super.key});

  @override
  State<RegisterWithInviteScreen> createState() =>
      _RegisterWithInviteScreenState();
}

class _RegisterWithInviteScreenState extends State<RegisterWithInviteScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      final token = Uri.base.queryParameters['token'];
      if (token != null && token.isNotEmpty) {
        _tokenCtrl.text = token;
      }
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final email = _emailCtrl.text.trim().toLowerCase();
    final password = _passCtrl.text;
    final token = _tokenCtrl.text.trim();

    if (email.isEmpty || password.isEmpty || token.isEmpty) {
      setState(
        () => _error = 'Please fill in email, password, and invite token',
      );
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Validate invite exists and is valid
      final inviteRef = FirebaseFirestore.instance
          .collection('invites')
          .doc(token);
      final inviteSnap = await inviteRef.get();
      if (!inviteSnap.exists) {
        setState(() => _error = 'Invalid invite token');
        return;
      }
      final inv = inviteSnap.data() as Map<String, dynamic>;
      if (inv['used'] == true) {
        setState(() => _error = 'Invite already used');
        return;
      }
      final ts = inv['expiresAt'];
      final expiresAt = ts is Timestamp ? ts.toDate() : null;
      if (expiresAt == null || expiresAt.isBefore(DateTime.now())) {
        setState(() => _error = 'Invite expired');
        return;
      }
      final invitedEmail = (inv['email'] ?? '').toString().toLowerCase();
      if (invitedEmail != email) {
        setState(() => _error = 'Invite email does not match');
        return;
      }

      // Create auth user
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      // await cred.user?.sendEmailVerification();
      final uid = cred.user!.uid;

      // Create user profile with inviteToken (validated by rules)
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'id': uid,
        'email': email,
        'displayName': null,
        'role': 'staff',
        'createdAt': FieldValue.serverTimestamp(),
        'lastLogin': FieldValue.serverTimestamp(),
        'emailVerified': false,
        'inviteToken': token,
      }, SetOptions(merge: true));

      // Mark invite as used
      await inviteRef.update({
        'used': true,
        'usedBy': uid,
        'usedAt': FieldValue.serverTimestamp(),
      });

      // Optionally remove inviteToken from user document
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'inviteToken': FieldValue.delete(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Registration successful. A verification email has been sent. Please check your inbox.',
          ),
        ),
      );
      Navigator.of(context).pop();
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? 'Failed to register');
    } catch (e) {
      setState(() => _error = 'Unexpected error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Register with Invite')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _passCtrl,
                    decoration: const InputDecoration(labelText: 'Password'),
                    obscureText: true,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _tokenCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Invite token',
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _loading ? null : _register,
                    child: _loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Create Account'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
