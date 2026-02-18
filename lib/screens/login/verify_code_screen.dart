import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class VerifyCodeScreen extends StatefulWidget {
  const VerifyCodeScreen({super.key});

  @override
  State<VerifyCodeScreen> createState() => _VerifyCodeScreenState();
}

class _VerifyCodeScreenState extends State<VerifyCodeScreen> {
  final _formKey = GlobalKey<FormState>();

  final List<TextEditingController> _digitCtrls = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _digitNodes = List.generate(6, (_) => FocusNode());

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _digitCtrls) {
      c.dispose();
    }
    for (final n in _digitNodes) {
      n.dispose();
    }
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _digitCtrls.map((c) => c.text.trim()).join();
    if (code.length != 6 || !RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() {
        _error = 'Code must be 6 digits';
      });
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _error = 'No user is currently signed in.';
        });
        return;
      }

      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);
      final snap = await docRef.get();
      if (!snap.exists) {
        setState(() {
          _error = 'User profile not found.';
        });
        return;
      }

      final data = snap.data() as Map<String, dynamic>;
      final storedCode = (data['verificationCode'] ?? '').toString();
      final expiresAt = data['verificationCodeExpiresAt'];

      if (storedCode.isEmpty) {
        setState(() {
          _error = 'No verification code found. Please register again.';
        });
        return;
      }

      if (storedCode != code) {
        setState(() {
          _error = 'Invalid verification code.';
        });
        return;
      }

      if (expiresAt is Timestamp) {
        final expiry = expiresAt.toDate();
        if (expiry.isBefore(DateTime.now())) {
          setState(() {
            _error = 'Verification code has expired. Please register again.';
          });
          return;
        }
      }

      await docRef.update({
        'verificationCodeVerified': true,
        'verificationCode': FieldValue.delete(),
        'verificationCodeExpiresAt': FieldValue.delete(),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Email verification successful. You can now sign in.'),
        ),
      );

      context.go('/login');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final size = MediaQuery.of(context).size;
    final isTablet = size.width > 600;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(title: const Text('Verify Email Code')),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(isTablet ? 32.0 : 16.0),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isTablet ? 440.0 : 360.0),
                child: Card(
                  elevation: 12,
                  shadowColor: colorScheme.shadow.withValues(alpha: 0.2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(isTablet ? 32.0 : 24.0),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Enter Verification Code',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'We have sent a 6-digit verification code to your email. Please enter it below to complete your registration.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.7,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: List.generate(6, (index) {
                              return SizedBox(
                                width: 44,
                                child: TextField(
                                  controller: _digitCtrls[index],
                                  focusNode: _digitNodes[index],
                                  textAlign: TextAlign.center,
                                  keyboardType: TextInputType.number,
                                  maxLength: 1,
                                  decoration: InputDecoration(
                                    counterText: '',
                                    filled: true,
                                    fillColor:
                                        colorScheme.surfaceContainerHighest,
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: colorScheme.outline,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: colorScheme.primary,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                  onChanged: (v) {
                                    final val = v.trim();
                                    if (val.length == 1) {
                                      if (index < 5) {
                                        _digitNodes[index + 1].requestFocus();
                                      } else {
                                        // Last digit entered: auto-submit if all boxes are filled
                                        final allFilled = _digitCtrls.every(
                                          (c) => c.text.trim().length == 1,
                                        );
                                        if (allFilled && !_submitting) {
                                          _verify();
                                        }
                                      }
                                    }
                                  },
                                ),
                              );
                            }),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 16),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: colorScheme.errorContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    color: colorScheme.onErrorContainer,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _error!,
                                      style: TextStyle(
                                        color: colorScheme.onErrorContainer,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                          SizedBox(
                            height: 56,
                            child: FilledButton(
                              onPressed: _submitting ? null : _verify,
                              style: FilledButton.styleFrom(
                                backgroundColor: colorScheme.primary,
                                foregroundColor: colorScheme.onPrimary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: _submitting
                                  ? SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              colorScheme.onPrimary,
                                            ),
                                      ),
                                    )
                                  : const Text(
                                      'Verify Code',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                "Didn't receive the code?",
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurface.withValues(
                                    alpha: 0.7,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: null,
                                child: const Text('Resend'),
                              ),
                            ],
                          ),
                          TextButton(
                            onPressed: () => context.go('/login'),
                            child: Text(
                              'Back to Sign In',
                              style: TextStyle(color: colorScheme.primary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
