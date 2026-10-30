import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/files.dart';
import '../core/i18n.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import 'pay.dart';

class FeesScreen extends StatefulWidget {
  const FeesScreen({super.key, required this.child, this.embedded = false, this.onChanged});

  final Map<String, dynamic> child;
  final bool embedded;
  final Future<void> Function()? onChanged;

  @override
  State<FeesScreen> createState() => _FeesScreenState();
}

class _FeesScreenState extends State<FeesScreen> {
  final _loader = GlobalKey<LoaderState<Map<String, dynamic>>>();
  final Set<int> _selected = {};
  bool _paying = false;
  int? _opening;

  int get _childId => widget.child['id'] as int;

  Future<void> _pay(List<Map<String, dynamic>> due, bool online) async {
    if (!online) {
      toast(context, 'Online payment is not available for this school yet. Please pay at the school office.');
      return;
    }

    final chosen = due.where((i) => _selected.contains(i['id'])).toList();
    if (chosen.isEmpty) return;

    final session = context.read<Session>();
    setState(() => _paying = true);
    try {
      final order = await session.api.post('/children/$_childId/fees/pay', {
        'amounts': {for (final i in chosen) '${i['id']}': i['balance']},
      }) as Map<String, dynamic>;

      final result = await openCheckout(
        keyId: order['key_id'] as String,
        orderId: order['order_id'] as String,
        amountPaise: order['amount_paise'] as int,
        schoolName: session.schoolName,
        description: 'Fees for ${widget.child['name']}',
        contact: session.user?['phone'] as String?,
      );
      if (result == null) return; // closed by the parent

      final done = await session.api.post('/fees/verify', result) as Map<String, dynamic>;
      _selected.clear();
      await _loader.currentState?.reload();
      await widget.onChanged?.call();
      if (mounted) toast(context, 'Payment received. Receipt no. ${done['receipt_no']}');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } catch (_) {
      if (mounted) toast(context, 'Payment did not go through. If money was deducted it will be updated automatically.', error: true);
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  Future<void> _openReceipt(Map<String, dynamic> receipt) async {
    setState(() => _opening = receipt['id'] as int);
    final bytes = await guard(context, () => apiOf(context).download(receipt['pdf_url'] as String));
    if (bytes != null) {
      final opened = await saveAndOpen(bytes, 'receipt-${receipt['receipt_no']}.pdf');
      if (!opened && mounted) toast(context, 'Install a PDF viewer to open receipts.', error: true);
    }
    if (mounted) setState(() => _opening = null);
  }

  @override
  Widget build(BuildContext context) {
    final api = apiOf(context);

    final body = Loader<Map<String, dynamic>>(
      key: _loader,
      load: () async => (await api.get('/children/$_childId/fees')) as Map<String, dynamic>,
      builder: (context, data, _) {
        final invoices = List<Map<String, dynamic>>.from((data['invoices'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
        final receipts = List<Map<String, dynamic>>.from((data['receipts'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
        final due = invoices.where((i) => (i['balance'] as num) > 0).toList();
        final online = data['online_payment_enabled'] == true;
        final totalDue = due.fold<num>(0, (sum, i) => sum + (i['balance'] as num));
        final selectedTotal = due.where((i) => _selected.contains(i['id'])).fold<num>(0, (sum, i) => sum + (i['balance'] as num));
        final today = DateUtils.dateOnly(DateTime.now());

        return Stack(
          children: [
            ListView(
              padding: EdgeInsets.fromLTRB(16, 4, 16, _selected.isEmpty ? 28 : 110),
              children: [
                Panel(
                  gradient: totalDue > 0 ? const LinearGradient(colors: [Color(0xFF1A2A6C), Color(0xFF2F5BFF)]) : const LinearGradient(colors: [Color(0xFF0E9F6E), Color(0xFF12B886)]),
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${tr('Fees due')} - ${widget.child['name']}', style: TextStyle(color: Colors.white.withValues(alpha: 0.85))),
                      const SizedBox(height: 4),
                      Text(totalDue > 0 ? money(totalDue) : tr('No dues'), style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                      if (totalDue > 0 && !online)
                        Padding(padding: const EdgeInsets.only(top: 8), child: Text('Pay at the school office. Online payment is not switched on yet.', style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13))),
                    ],
                  ),
                ),
                if (due.isNotEmpty) SectionTitle(tr('Due')),
                for (final invoice in due)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Builder(builder: (context) {
                      final id = invoice['id'] as int;
                      final dueDate = DateTime.tryParse(invoice['due_date'] as String);
                      final overdue = dueDate != null && dueDate.isBefore(today);
                      final checked = _selected.contains(id);
                      return Panel(
                        borderColor: checked ? Brand.current.primary : null,
                        onTap: online ? () => setState(() => checked ? _selected.remove(id) : _selected.add(id)) : null,
                        child: Row(
                          children: [
                            if (online) Padding(padding: const EdgeInsets.only(right: 10), child: Icon(checked ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: checked ? Brand.current.primary : AppColors.line, size: 28)),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(invoice['title'] as String, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                                  const SizedBox(height: 4),
                                  Wrap(spacing: 6, runSpacing: 4, children: [
                                    Pill('${overdue ? 'Was due' : 'Due'} ${niceDate(invoice['due_date'] as String)}', color: overdue ? AppColors.red : AppColors.soft),
                                    if ((invoice['fine'] as num) > 0) Pill('Fine ${money(invoice['fine'] as num)}', color: AppColors.red),
                                    if ((invoice['concession'] as num) > 0) Pill('Concession ${money(invoice['concession'] as num)}', color: AppColors.green),
                                  ]),
                                ],
                              ),
                            ),
                            Text(money(invoice['balance'] as num), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                          ],
                        ),
                      );
                    }),
                  ),
                SectionTitle(tr('Receipts')),
                if (receipts.isEmpty) const Panel(child: Text('No payments yet.', style: TextStyle(color: AppColors.soft))),
                for (final receipt in receipts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Panel(
                      onTap: () => _openReceipt(receipt),
                      child: Row(
                        children: [
                          const IconBadge(Icons.receipt_long_rounded, color: AppColors.green),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(money(receipt['amount'] as num), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                                Text('${receipt['receipt_no']} - ${niceDate(receipt['paid_at'] as String?)}', style: const TextStyle(color: AppColors.soft, fontSize: 13)),
                              ],
                            ),
                          ),
                          _opening == receipt['id'] ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Icon(Icons.download_rounded, color: AppColors.soft),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            if (_selected.isNotEmpty)
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: FilledButton(
                  onPressed: _paying ? null : () => _pay(due, online),
                  child: _paying ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : Text('${tr('Pay now')}  ${money(selectedTotal)}'),
                ),
              ),
          ],
        );
      },
    );

    if (widget.embedded) {
      return Scaffold(appBar: AppBar(title: Text(tr('Fees')), automaticallyImplyLeading: false), body: KeyedSubtree(key: ValueKey(_childId), child: body));
    }
    return AppPage(title: tr('Fees'), body: body);
  }
}
