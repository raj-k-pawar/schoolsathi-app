import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

/// Choose your own password. Shown straight after the first sign-in with the school's slip,
/// and from Profile at any time.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key, this.firstTime = false});

  final bool firstTime;

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  bool _busy = false;
  bool _show = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  String? _check() {
    final p = _password.text;
    if (_current.text.isEmpty) return widget.firstTime ? 'Enter the password from your slip.' : 'Enter your current password.';
    if (p.length < 8) return 'The new password needs at least 8 characters.';
    if (!RegExp(r'[A-Za-z]').hasMatch(p) || !RegExp(r'\d').hasMatch(p)) return 'Use both letters and numbers in the new password.';
    if (p == _current.text) return 'Choose a password different from the one the school gave you.';
    if (p != _repeat.text) return 'The two new passwords are not the same.';
    return null;
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final problem = _check();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<Session>().changePassword(_current.text, _password.text);
      if (!mounted) return;
      toast(context, 'Password changed.');
      if (!widget.firstTime) Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.firstTime ? 'Set your password' : 'Change password'),
        automaticallyImplyLeading: !widget.firstTime,
        actions: [
          if (widget.firstTime) TextButton(onPressed: session.logout, child: const Text('Sign out')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          if (widget.firstTime)
            Panel(
              gradient: Brand.current.gradient,
              padding: const EdgeInsets.all(18),
              child: Row(children: [
                const Icon(Icons.lock_reset_rounded, color: Colors.white, size: 36),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Welcome, ${session.userName}! Please choose your own password. Keep it secret - it protects your child\'s details.',
                    style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.35, fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
            ),
          const SizedBox(height: 18),
          if (_error != null)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
              child: Text(_error!, style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w600)),
            ),
          TextField(
            controller: _current,
            obscureText: !_show,
            decoration: InputDecoration(labelText: widget.firstTime ? 'Password from the slip' : 'Current password', prefixIcon: const Icon(Icons.key_rounded)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: !_show,
            decoration: const InputDecoration(labelText: 'New password', helperText: 'At least 8 characters, letters and numbers', prefixIcon: Icon(Icons.lock_outline_rounded)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _repeat,
            obscureText: !_show,
            decoration: const InputDecoration(labelText: 'Repeat new password', prefixIcon: Icon(Icons.lock_outline_rounded)),
            onSubmitted: (_) => _save(),
          ),
          CheckboxListTile(
            value: _show,
            onChanged: (v) => setState(() => _show = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Show passwords'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : const Text('Save password'),
          ),
        ],
      ),
    );
  }
}
