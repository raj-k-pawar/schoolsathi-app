import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/config.dart';
import '../core/i18n.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _login = TextEditingController();
  final _password = TextEditingController();

  bool _busy = false;
  bool _show = false;
  String? _error;
  List<Account>? _accounts;

  @override
  void dispose() {
    _login.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signIn() => _run(() async {
        if (_login.text.trim().isEmpty || _password.text.isEmpty) throw ApiException('Enter your login ID (or mobile number) and password.');
        await _finish(await context.read<Session>().passwordLogin(_login.text.trim(), _password.text));
      });

  void _forgot() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Forgot password?'),
        content: const Text('Please ask your school office for a new password; you can then choose your own. Staff with a website login can also use "Forgot password" on the school website.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ),
    );
  }

  Future<void> _finish(List<Account> accounts) async {
    if (accounts.length == 1) {
      await context.read<Session>().useAccount(accounts.first);
    } else {
      // The same number is registered in more than one school: let the user pick.
      _accounts = accounts;
    }
  }

  Future<void> _serverDialog() async {
    final session = context.read<Session>();
    final controller = TextEditingController(text: session.serverUrl);
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('School server address'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Change this only if your school office asked you to.', style: TextStyle(color: AppColors.soft)),
            const SizedBox(height: 12),
            TextField(controller: controller, keyboardType: TextInputType.url, autocorrect: false, decoration: const InputDecoration(hintText: 'https://school.example.com')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancel'))),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(100, 44)), onPressed: () => Navigator.pop(context, controller.text), child: Text(tr('Save'))),
        ],
      ),
    );
    if (url == null) return;
    // Released apps talk only to secure (https) servers; plain http is for testing builds.
    if (!url.trim().startsWith(kDebugMode ? 'http' : 'https://')) {
      if (mounted) toast(context, 'The address must start with https://', error: true);
      return;
    }
    if (url.trim().startsWith('http')) {
      await session.setServerUrl(url);
      if (mounted) toast(context, 'Server address saved.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final brand = Brand.current;
    final session = context.watch<Session>();

    return Scaffold(
      backgroundColor: brand.dark,
      body: Container(
        decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [brand.dark, Color.lerp(brand.dark, brand.primary, 0.75)!, brand.secondary])),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: _LanguageButton(current: I18n.locale, onPick: session.setLocale),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onLongPress: _serverDialog,
                      child: Column(
                        children: [
                          Container(
                            width: 84,
                            height: 84,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(26),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                            ),
                            child: Icon(_logoIcon, color: Colors.white, size: 44),
                          ),
                          const SizedBox(height: 18),
                          Text(AppConfig.appName, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
                          const SizedBox(height: 6),
                          Text(AppConfig.tagline, textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 15)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: 40, offset: const Offset(0, 20))],
                      ),
                      child: AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        alignment: Alignment.topCenter,
                        child: _accounts != null ? _accountPicker(session) : _form(),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text('Your login ID and first password are on the slip from your school.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 12.5)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData get _logoIcon => Icons.school_rounded;

  Widget _errorBox() {
    if (_error == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.red, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(_error!, style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  Widget _form() {
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(tr('Sign in'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('Use the login ID or mobile number and password from your school.', style: TextStyle(color: AppColors.soft)),
          const SizedBox(height: 18),
          _errorBox(),
          TextField(
            controller: _login,
            keyboardType: TextInputType.visiblePassword,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.username],
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            decoration: const InputDecoration(labelText: 'Login ID or mobile number', hintText: 'e.g. dps1023 or 9820012345', prefixIcon: Icon(Icons.person_outline_rounded)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: !_show,
            autocorrect: false,
            enableSuggestions: false,
            autofillHints: const [AutofillHints.password],
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                tooltip: _show ? 'Hide password' : 'Show password',
                onPressed: () => setState(() => _show = !_show),
                icon: Icon(_show ? Icons.visibility_off_rounded : Icons.visibility_rounded),
              ),
            ),
            onSubmitted: (_) => _signIn(),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _busy ? null : _signIn,
            child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : Text(tr('Sign in')),
          ),
          TextButton(onPressed: _forgot, child: const Text('Forgot password?')),
        ],
      ),
    );
  }

  Widget _accountPicker(Session session) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Choose your school', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
        for (final account in _accounts!)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Panel(
              onTap: () => session.useAccount(account),
              child: Row(
                children: [
                  const IconBadge(Icons.apartment_rounded),
                  const SizedBox(width: 12),
                  Expanded(child: Text((account.school?['name'] as String?) ?? 'School', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.soft),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _LanguageButton extends StatelessWidget {
  const _LanguageButton({required this.current, required this.onPick});

  final String current;
  final void Function(String) onPick;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: onPick,
      itemBuilder: (_) => [for (final e in I18n.names.entries) PopupMenuItem(value: e.key, child: Text(e.value))],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.translate_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 6),
            Text(I18n.names[current] ?? 'English', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
