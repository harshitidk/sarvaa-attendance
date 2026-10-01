import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../state/auth_controller.dart';
import '../widgets/common.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.auth});

  final AuthController auth;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Enter your work email and password.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final error = await widget.auth.signIn(_email.text.trim(), _password.text);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: Insets.gutter),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Spacer(flex: 2),
                    // Wordmark: an ink square, the same gesture as the "present"
                    // status. The brand and the system share one language.
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        height: 44,
                        width: 44,
                        decoration: BoxDecoration(
                          color: AppColors.ink,
                          borderRadius: BorderRadius.circular(Radii.md),
                        ),
                        child: Icon(
                          Icons.location_on,
                          color: AppColors.onInk,
                          size: 22,
                        ),
                      ),
                    ),
                    const SizedBox(height: Insets.xxl),
                    Text(
                      'Attendance',
                      style: AppText.title.copyWith(fontSize: 34),
                    ),
                    const SizedBox(height: Insets.sm),
                    Text(
                      'Your hours are recorded automatically as you arrive at and '
                      'leave the workplace.',
                      style: AppText.body,
                    ),
                    const SizedBox(height: Insets.huge),
                    const FieldLabel('Work email'),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      enableSuggestions: false,
                      onSubmitted: (_) => _passwordFocus.requestFocus(),
                      decoration: const InputDecoration(
                        hintText: 'you@company.com',
                      ),
                    ),
                    const SizedBox(height: Insets.xl),
                    const FieldLabel('Password'),
                    TextField(
                      controller: _password,
                      focusNode: _passwordFocus,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.go,
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        hintText: '••••••••',
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _obscure = !_obscure),
                          tooltip: _obscure ? 'Show password' : 'Hide password',
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: Insets.lg),
                      Notice(_error!, tone: NoticeTone.alert),
                    ],
                    const SizedBox(height: Insets.xxl),
                    BusyButton(
                      label: 'Sign in',
                      busy: _loading,
                      onPressed: _submit,
                    ),
                    const Spacer(flex: 3),
                    Padding(
                      padding: const EdgeInsets.only(bottom: Insets.lg),
                      child: Text(
                        'You will be asked for location permission after signing in.',
                        textAlign: TextAlign.center,
                        style: AppText.bodySm.copyWith(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
