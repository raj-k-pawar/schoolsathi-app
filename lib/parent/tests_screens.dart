import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/i18n.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

class TestsScreen extends StatelessWidget {
  const TestsScreen({super.key, required this.child});

  final Map<String, dynamic> child;

  @override
  Widget build(BuildContext context) {
    final api = apiOf(context);

    return AppPage(
      title: tr('Online tests'),
      body: Loader<List<dynamic>>(
        load: () async => ((await api.get('/children/${child['id']}/tests')) as Map<String, dynamic>)['tests'] as List<dynamic>,
        builder: (context, tests, reload) {
          if (tests.isEmpty) return EmptyState(icon: Icons.quiz_rounded, title: tr('Nothing here yet'), subtitle: 'Online tests from teachers appear here.');
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
            itemCount: tests.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final test = Map<String, dynamic>.from(tests[i] as Map);
              final submitted = test['status'] == 'submitted';
              final openNow = test['open_now'] == true;
              return Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const IconBadge(Icons.quiz_rounded, color: Color(0xFF0AA5C2)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(test['title'] as String, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                          Text('${test['subject'] ?? 'General'} - ${test['questions']} questions - ${test['duration_minutes']} min', style: const TextStyle(color: AppColors.soft, fontSize: 13)),
                        ]),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    if (submitted)
                      Row(children: [
                        const Pill('Submitted', color: AppColors.green, icon: Icons.check_rounded),
                        const Spacer(),
                        Text('${test['score']} / ${test['max_score']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                      ])
                    else if (!openNow)
                      Pill(test['closes_at'] != null && DateTime.parse(test['closes_at'] as String).isBefore(DateTime.now()) ? 'Closed' : 'Opens ${niceDate(test['opens_at'] as String?, pattern: 'd MMM, h:mm a')}', color: AppColors.soft)
                    else
                      FilledButton(
                        onPressed: () async {
                          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => TakeTestScreen(childId: child['id'] as int, test: test)));
                          reload();
                        },
                        child: Text(test['status'] == 'in_progress' ? 'Continue test' : 'Start test'),
                      ),
                    if (!submitted && openNow && test['closes_at'] != null)
                      Padding(padding: const EdgeInsets.only(top: 8), child: Text('Open until ${niceDate(test['closes_at'] as String?, pattern: 'd MMM, h:mm a')}', style: const TextStyle(color: AppColors.soft, fontSize: 12))),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class TakeTestScreen extends StatefulWidget {
  const TakeTestScreen({super.key, required this.childId, required this.test});

  final int childId;
  final Map<String, dynamic> test;

  @override
  State<TakeTestScreen> createState() => _TakeTestScreenState();
}

class _TakeTestScreenState extends State<TakeTestScreen> {
  List<Map<String, dynamic>>? _questions;
  final Map<int, int> _answers = {};
  int _index = 0;
  int _secondsLeft = 0;
  Timer? _timer;
  String? _error;
  bool _submitting = false;
  Map<String, dynamic>? _result;

  String get _base => '/children/${widget.childId}/tests/${widget.test['id']}';

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final data = await apiOf(context).post('$_base/start') as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _questions = List<Map<String, dynamic>>.from((data['questions'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
        _secondsLeft = data['seconds_left'] as int;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_secondsLeft <= 1) {
          _timer?.cancel();
          _submit(auto: true);
        } else {
          setState(() => _secondsLeft--);
        }
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _submit({bool auto = false}) async {
    if (_submitting || _result != null) return;

    if (!auto) {
      final unanswered = _questions!.length - _answers.length;
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Submit the test?'),
          content: Text(unanswered > 0 ? '$unanswered question(s) are not answered. You cannot change answers after submitting.' : 'You cannot change answers after submitting.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Go back')),
            FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(110, 44)), onPressed: () => Navigator.pop(context, true), child: const Text('Submit')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }

    setState(() => _submitting = true);
    _timer?.cancel();
    try {
      final data = await apiOf(context).post('$_base/submit', {'answers': {for (final e in _answers.entries) '${e.key}': e.value}}) as Map<String, dynamic>;
      if (mounted) setState(() => _result = data);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_result != null) return _resultView();
    if (_error != null) return AppPage(title: widget.test['title'] as String, body: EmptyState(icon: Icons.info_outline_rounded, title: _error!, action: 'Back', onAction: () => Navigator.pop(context)));
    if (_questions == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final question = _questions![_index];
    final id = question['id'] as int;
    final options = List<String>.from(question['options'] as List);
    final low = _secondsLeft < 60;
    final last = _index == _questions!.length - 1;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) toast(context, 'Submit the test to leave. The timer keeps running.');
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text('Question ${_index + 1} of ${_questions!.length}'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Center(child: Pill('${(_secondsLeft ~/ 60).toString().padLeft(2, '0')}:${(_secondsLeft % 60).toString().padLeft(2, '0')}', color: low ? AppColors.red : AppColors.ink, icon: Icons.timer_outlined, solid: low)),
            ),
          ],
          bottom: PreferredSize(preferredSize: const Size.fromHeight(4), child: LinearProgressIndicator(value: (_index + 1) / _questions!.length, minHeight: 4, backgroundColor: AppColors.line)),
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(18),
                  children: [
                    Pill('${question['marks']} mark(s)', color: AppColors.soft),
                    const SizedBox(height: 10),
                    Text(question['question'] as String, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, height: 1.4)),
                    const SizedBox(height: 20),
                    for (var i = 0; i < options.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Panel(
                          borderColor: _answers[id] == i ? Brand.current.primary : null,
                          color: _answers[id] == i ? Brand.current.primary.withValues(alpha: 0.06) : Colors.white,
                          onTap: () => setState(() => _answers[id] = i),
                          child: Row(children: [
                            Container(
                              width: 34,
                              height: 34,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: _answers[id] == i ? Brand.current.primary : AppColors.bg, shape: BoxShape.circle),
                              child: Text(String.fromCharCode(65 + i), style: TextStyle(fontWeight: FontWeight.w800, color: _answers[id] == i ? Colors.white : AppColors.soft)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Text(options[i], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                          ]),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                child: Row(children: [
                  if (_index > 0) Expanded(child: OutlinedButton(onPressed: () => setState(() => _index--), child: const Text('Previous'))),
                  if (_index > 0) const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: _submitting ? null : (last ? _submit : () => setState(() => _index++)),
                      child: _submitting ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : Text(last ? 'Submit test' : 'Next'),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resultView() {
    final score = _result!['score'] as num;
    final max = _result!['max_score'] as num;
    final percent = max > 0 ? (score * 100 / max).round() : 0;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: Brand.current.gradient),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.emoji_events_rounded, color: Colors.white, size: 84),
                  const SizedBox(height: 16),
                  const Text('Test submitted', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text('$score / $max', style: const TextStyle(color: Colors.white, fontSize: 52, fontWeight: FontWeight.w800)),
                  Text('$percent%', style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 20, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 28),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.ink),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Done'),
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
