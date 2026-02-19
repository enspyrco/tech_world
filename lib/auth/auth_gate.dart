import 'dart:async' show Timer;
import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuthException;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:tech_world/auth/auth_service.dart';
import 'package:tech_world/utils/locator.dart';

/// Helper class to show a snackbar using the passed context.
class ScaffoldSnackbar {
  ScaffoldSnackbar(this._context);

  /// The scaffold of current context.
  factory ScaffoldSnackbar.of(BuildContext context) {
    return ScaffoldSnackbar(context);
  }

  final BuildContext _context;

  /// Helper method to show a SnackBar.
  void show(String message) {
    ScaffoldMessenger.of(_context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }
}

/// The mode of the current auth session, either [AuthMode.login] or [AuthMode.register].
enum AuthMode { login, register }

extension on AuthMode {
  String get label => this == AuthMode.login ? 'Sign in' : 'Register';
}

/// Entrypoint sign-in flows with Firebase.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<StatefulWidget> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  TextEditingController emailController = TextEditingController();
  TextEditingController passwordController = TextEditingController();

  GlobalKey<FormState> formKey = GlobalKey<FormState>();
  String error = '';
  String verificationId = '';
  Timer? _errorTimer;

  AuthMode mode = AuthMode.login;

  bool isLoading = false;

  bool get _isApplePlatform => !kIsWeb && (Platform.isIOS || Platform.isMacOS);

  @override
  void dispose() {
    _errorTimer?.cancel();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  void _setError(String message) {
    _errorTimer?.cancel();
    setState(() {
      error = message;
    });
    _errorTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          error = '';
        });
      }
    });
  }

  void setIsLoading() {
    if (mounted) {
      setState(() {
        isLoading = !isLoading;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: FocusScope.of(context).unfocus,
      child: Scaffold(
        body: Center(
          child: SingleChildScrollView(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SafeArea(
                  child: Form(
                    key: formKey,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 400),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            child: error.isNotEmpty
                                ? MaterialBanner(
                                    key: ValueKey(error),
                                    backgroundColor:
                                        Theme.of(context).colorScheme.error,
                                    content: SelectableText(error),
                                    actions: [
                                      TextButton(
                                        onPressed: () {
                                          _errorTimer?.cancel();
                                          setState(() {
                                            error = '';
                                          });
                                        },
                                        child: const Text(
                                          'dismiss',
                                          style:
                                              TextStyle(color: Colors.white),
                                        ),
                                      ),
                                    ],
                                    contentTextStyle:
                                        const TextStyle(color: Colors.white),
                                    padding: const EdgeInsets.all(10),
                                  )
                                : const SizedBox.shrink(),
                          ),
                          const SizedBox(height: 20),
                          Column(
                            children: [
                              TextFormField(
                                controller: emailController,
                                decoration: const InputDecoration(
                                  hintText: 'Email',
                                  border: OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.emailAddress,
                                autofillHints: const [AutofillHints.email],
                                validator: (value) =>
                                    value != null && value.isNotEmpty
                                        ? null
                                        : 'Required',
                              ),
                              const SizedBox(height: 20),
                              TextFormField(
                                controller: passwordController,
                                obscureText: true,
                                decoration: const InputDecoration(
                                  hintText: 'Password',
                                  border: OutlineInputBorder(),
                                ),
                                validator: (value) =>
                                    value != null && value.isNotEmpty
                                        ? null
                                        : 'Required',
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed:
                                  isLoading ? null : () => _emailAndPassword(),
                              child: isLoading
                                  ? const CircularProgressIndicator.adaptive()
                                  : Text(mode.label),
                            ),
                          ),
                          if (mode == AuthMode.login)
                            TextButton(
                              onPressed: _resetPassword,
                              child: const Text('Forgot password?'),
                            ),
                          const SizedBox(height: 20),
                          RichText(
                            text: TextSpan(
                              style: Theme.of(context).textTheme.bodyLarge,
                              children: [
                                TextSpan(
                                  text: mode == AuthMode.login
                                      ? "Don't have an account? "
                                      : 'You have an account? ',
                                ),
                                TextSpan(
                                  text: mode == AuthMode.login
                                      ? 'Register now'
                                      : 'Click to login',
                                  style: const TextStyle(color: Colors.blue),
                                  recognizer: TapGestureRecognizer()
                                    ..onTap = () {
                                      setState(() {
                                        mode = mode == AuthMode.login
                                            ? AuthMode.register
                                            : AuthMode.login;
                                      });
                                    },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          RichText(
                            text: TextSpan(
                              style: Theme.of(context).textTheme.bodyLarge,
                              children: [
                                const TextSpan(text: 'Or '),
                                TextSpan(
                                  text: 'continue as guest',
                                  style: const TextStyle(color: Colors.blue),
                                  recognizer: TapGestureRecognizer()
                                    ..onTap = _anonymousAuth,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Divider(),
                          const SizedBox(height: 10),
                          // Show Apple Sign In on Apple platforms
                          if (_isApplePlatform)
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: SignInWithAppleButton(
                                onPressed: _signInWithApple,
                              ),
                            ),
                          // Show Google Sign In on all platforms
                          if (_isApplePlatform) const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton.icon(
                              onPressed: isLoading ? null : _signInWithGoogle,
                              icon: Image.network(
                                'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
                                height: 24,
                                width: 24,
                                errorBuilder: (context, error, stackTrace) =>
                                    const Icon(Icons.g_mobiledata),
                              ),
                              label: const Text('Sign in with Google'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black87,
                              ),
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

  Future _resetPassword() async {
    String? email;
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Send'),
            ),
          ],
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter your email'),
              const SizedBox(height: 20),
              TextFormField(
                onChanged: (value) {
                  email = value;
                },
              ),
            ],
          ),
        );
      },
    );

    if (email != null) {
      try {
        await locate<AuthService>().sendPasswordReset(email: email!);
        if (mounted) {
          ScaffoldSnackbar.of(context).show('Password reset email is sent');
        }
      } catch (e) {
        if (mounted) {
          ScaffoldSnackbar.of(context).show('Error resetting');
        }
      }
    }
  }

  Future<void> _anonymousAuth() async {
    setIsLoading();

    try {
      await locate<AuthService>().signInAnonymously();
    } catch (e) {
      _setError('Could not sign in as guest. Please try again.');
    } finally {
      setIsLoading();
    }
  }

  Future<void> _emailAndPassword() async {
    if (formKey.currentState?.validate() ?? false) {
      setIsLoading();
      try {
        if (mode == AuthMode.login) {
          await locate<AuthService>().signInWithEmailAndPassword(
              email: emailController.text, password: passwordController.text);
        } else if (mode == AuthMode.register) {
          await locate<AuthService>().createUserWithEmailAndPassword(
              email: emailController.text, password: passwordController.text);
        }
      } on FirebaseAuthException catch (e) {
        _setError(_friendlyAuthError(e.code));
      } catch (e) {
        _setError(_friendlyAuthError('$e'));
      } finally {
        setIsLoading();
      }
    }
  }

  /// Maps Firebase Auth error codes to user-friendly messages.
  String _friendlyAuthError(String code) {
    return switch (code) {
      'user-not-found' => 'No account found with that email.',
      'wrong-password' => 'Incorrect password. Please try again.',
      'invalid-credential' => 'Invalid email or password. Please try again.',
      'email-already-in-use' => 'An account already exists with that email.',
      'weak-password' => 'Password is too weak. Use at least 6 characters.',
      'invalid-email' => 'Please enter a valid email address.',
      'too-many-requests' =>
        'Too many attempts. Please wait a moment and try again.',
      'network-request-failed' =>
        'Network error. Please check your connection.',
      _ => 'Something went wrong. Please try again.',
    };
  }

  Future<void> _signInWithApple() async {
    setIsLoading();
    try {
      await locate<AuthService>().signInWithApple();
    } catch (e) {
      _setError('Apple sign-in failed. Please try again.');
    } finally {
      setIsLoading();
    }
  }

  Future<void> _signInWithGoogle() async {
    setIsLoading();
    try {
      await locate<AuthService>().signInWithGoogle();
    } catch (e) {
      _setError('Google sign-in failed. Please try again.');
    } finally {
      setIsLoading();
    }
  }
}
