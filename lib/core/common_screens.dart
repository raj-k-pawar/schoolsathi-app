import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/change_password_screen.dart';

import 'alert_links.dart';
import 'config.dart';
import 'i18n.dart';
import 'session.dart';
import 'theme.dart';
import 'widgets.dart';

/// Alert inbox: everything the school has sent to this user.
class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key, this.embedded = false});

  /// True when shown as a tab (no back arrow).
  final bool embedded;

  static IconData iconFor(String type) {
    if (type.startsWith('attendance')) return Icons.how_to_reg_rounded;
    if (type.startsWith('fee')) return Icons.receipt_long_rounded;
    if (type.startsWith('bus')) return Icons.directions_bus_rounded;
    if (type.startsWith('homework')) return Icons.menu_book_rounded;
    if (type.startsWith('leave')) return Icons.event_busy_rounded;
    if (type.startsWith('exam')) return Icons.emoji_events_rounded;
    if (type.startsWith('chat')) return Icons.chat_bubble_rounded;
    if (type.startsWith('test')) return Icons.quiz_rounded;
    if (type.startsWith('dismissal')) return Icons.transfer_within_a_station_rounded;
    return Icons.campaign_rounded;
  }

  static Color colorFor(String type) {
    if (type.contains('absent') || type.contains('sos') || type.contains('missed') || type.contains('overdue') || type.contains('rejected') || type.contains('refused')) return AppColors.red;
    if (type.startsWith('bus')) return AppColors.amber;
    if (type.startsWith('fee')) return AppColors.blue;
    if (type.startsWith('attendance') || type.contains('approved')) return AppColors.green;
    return const Color(0xFF7A4DFF);
  }

  @override
  Widget build(BuildContext context) {
    final api = apiOf(context);

    final body = Loader<List<dynamic>>(
      load: () async {
        final data = await api.get('/alerts') as Map<String, dynamic>;
        if ((data['unread'] as int? ?? 0) > 0) {
          api.post('/alerts/read').catchError((_) => null);
        }
        return data['alerts'] as List<dynamic>;
      },
      builder: (context, alerts, reload) {
        if (alerts.isEmpty) {
          return EmptyState(icon: Icons.notifications_none_rounded, title: tr('Nothing here yet'), subtitle: 'Alerts from the school appear here.');
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: alerts.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final alert = alerts[i] as Map<String, dynamic>;
            final type = alert['type'] as String? ?? '';
            return Panel(
              // Tap to open what the alert is about (attendance, fees, bus, chat, SOS ...).
              onTap: () => openAlert(context, alert),
              color: alert['read'] == true ? Colors.white : colorFor(type).withValues(alpha: 0.05),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconBadge(iconFor(type), color: colorFor(type)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(alert['title'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                        const SizedBox(height: 2),
                        Text(alert['body'] as String? ?? '', style: const TextStyle(color: AppColors.soft, height: 1.35)),
                        const SizedBox(height: 6),
                        Text(
                          niceDate(alert['created_at'] as String?, pattern: 'd MMM, h:mm a'),
                          style: const TextStyle(color: AppColors.soft, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.soft),
                ],
              ),
            );
          },
        );
      },
    );

    if (embedded) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('Alerts')), automaticallyImplyLeading: false),
        body: body,
      );
    }
    return AppPage(title: tr('Alerts'), body: body);
  }
}

/// Profile: who is signed in, language, sign out. Extra rows can be added per app.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, this.extra = const [], this.embedded = true});

  final List<Widget> extra;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final brand = Brand.current;

    return Scaffold(
      appBar: AppBar(title: Text(tr('Profile')), automaticallyImplyLeading: !embedded),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Panel(
            gradient: brand.gradient,
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
                  child: Text(
                    session.userName.isEmpty ? '?' : session.userName[0].toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.userName,
                        style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800),
                      ),
                      Text((session.user?['phone'] as String?) ?? (session.user?['email'] as String?) ?? '', style: TextStyle(color: Colors.white.withValues(alpha: 0.85))),
                      const SizedBox(height: 4),
                      Text(session.schoolName, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (session.modes.length > 1) ...[
            // One app for everyone: a teacher who is also a parent, or staff setting up the gate tablet.
            Panel(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('Use the app as', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 4),
                RadioGroup<AppKind>(
                  groupValue: session.mode,
                  onChanged: (value) async {
                    if (value == null || value == session.mode) return;
                    Navigator.of(context).popUntil((route) => route.isFirst);
                    await session.setMode(value);
                  },
                  child: Column(children: [
                    for (final m in session.modes)
                      RadioListTile<AppKind>(
                        contentPadding: EdgeInsets.zero,
                        value: m,
                        title: Text(AppConfig.modeLabel(m), style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(AppConfig.modeHint(m)),
                      ),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 16),
          ],
          ...extra,
          Panel(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const IconBadge(Icons.notifications_rounded),
                  title: Text(tr('Notifications'), style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('Everything the school has sent you'),
                  trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.soft),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AlertsScreen())),
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const IconBadge(Icons.lock_rounded),
                  title: Text(tr('Change password'), style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('Login ID: ${session.user?['username'] ?? '-'}'),
                  trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.soft),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChangePasswordScreen())),
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const IconBadge(Icons.translate_rounded),
                  title: Text(tr('Language'), style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('Alerts from the school also come in this language'),
                  trailing: DropdownButton<String>(
                    value: I18n.locale,
                    underline: const SizedBox.shrink(),
                    items: [for (final e in I18n.names.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                    onChanged: (value) => value == null ? null : session.setLocale(value),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(tr('Sign out')),
                  content: const Text('Do you want to sign out of this phone?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Cancel'))),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(tr('Sign out'), style: const TextStyle(color: AppColors.red)),
                    ),
                  ],
                ),
              );
              if (ok == true && context.mounted) {
                Navigator.of(context).popUntil((route) => route.isFirst);
                await session.logout();
              }
            },
            icon: const Icon(Icons.logout_rounded, color: AppColors.red),
            label: Text(tr('Sign out'), style: const TextStyle(color: AppColors.red)),
          ),
          const SizedBox(height: 18),
          Center(
            child: Text('${AppConfig.appName} 1.0.0', style: const TextStyle(color: AppColors.soft, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
