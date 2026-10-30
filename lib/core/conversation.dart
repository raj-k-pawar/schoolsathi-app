import 'dart:async';

import 'package:flutter/material.dart';

import 'i18n.dart';
import 'theme.dart';
import 'widgets.dart';

/// A chat thread. Used by parents (with a teacher) and by teachers (with a parent).
/// New messages are fetched every 6 seconds while the screen is open.
class ConversationScreen extends StatefulWidget {
  const ConversationScreen({super.key, required this.title, this.subtitle, required this.path, this.notice});

  final String title;
  final String? subtitle;

  /// API path of the thread's messages, used for both loading and sending.
  final String path;

  /// Shown above the input, for example the chat hours.
  final String? notice;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 6), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final lastId = _messages.isEmpty ? null : _messages.last['id'];
      final data = await apiOf(context).get(widget.path, query: {if (lastId != null) 'after_id': lastId}) as Map<String, dynamic>;
      final fresh = List<Map<String, dynamic>>.from((data['messages'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
      if (!mounted) return;
      setState(() {
        _messages = [..._messages, ...fresh];
        _loading = false;
        _error = null;
      });
      if (fresh.isNotEmpty) _toBottom();
    } catch (e) {
      if (mounted && !silent) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final ok = await guard(context, () => apiOf(context).post(widget.path, {'body': text}));
    if (ok != null) {
      _input.clear();
      await _load(silent: true);
    }
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final brand = Brand.current;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            Avatar(name: widget.title, radius: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  if (widget.subtitle != null) Text(widget.subtitle!, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.soft, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null && _messages.isEmpty
                      ? EmptyState(icon: Icons.cloud_off_rounded, title: _error!, action: tr('Retry'), onAction: _load)
                      : _messages.isEmpty
                          ? const EmptyState(icon: Icons.forum_outlined, title: 'No messages yet', subtitle: 'Say hello to start the conversation.')
                          : ListView.builder(
                              controller: _scroll,
                              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                              itemCount: _messages.length,
                              itemBuilder: (context, i) {
                                final message = _messages[i];
                                final mine = message['mine'] == true;
                                return Align(
                                  alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                                  child: Container(
                                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                                    decoration: BoxDecoration(
                                      gradient: mine ? brand.gradient : null,
                                      color: mine ? null : Colors.white,
                                      border: mine ? null : Border.all(color: AppColors.line),
                                      borderRadius: BorderRadius.only(
                                        topLeft: const Radius.circular(18),
                                        topRight: const Radius.circular(18),
                                        bottomLeft: Radius.circular(mine ? 18 : 4),
                                        bottomRight: Radius.circular(mine ? 4 : 18),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Align(alignment: Alignment.centerLeft, child: Text(message['body'] as String, style: TextStyle(color: mine ? Colors.white : AppColors.ink, height: 1.35))),
                                        const SizedBox(height: 3),
                                        Text(niceDate(message['sent_at'] as String?, pattern: 'd MMM, h:mm a'), style: TextStyle(fontSize: 10.5, color: mine ? Colors.white70 : AppColors.soft)),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
            ),
            if (widget.notice != null)
              Container(
                width: double.infinity,
                color: AppColors.amber.withValues(alpha: 0.14),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(widget.notice!, style: const TextStyle(color: Color(0xFF8A5A00), fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 2000,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(hintText: tr('Type a message'), counterText: '', fillColor: AppColors.bg, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    style: IconButton.styleFrom(backgroundColor: brand.primary, minimumSize: const Size(48, 48)),
                    icon: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
