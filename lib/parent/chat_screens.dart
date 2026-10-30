import 'package:flutter/material.dart';

import '../core/conversation.dart';
import '../core/i18n.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

class ChatTeachersScreen extends StatelessWidget {
  const ChatTeachersScreen({super.key, required this.child});

  final Map<String, dynamic> child;

  @override
  Widget build(BuildContext context) {
    final api = apiOf(context);
    final childId = child['id'];

    return AppPage(
      title: tr('Chat'),
      body: Loader<Map<String, dynamic>>(
        load: () async => (await api.get('/children/$childId/chat')) as Map<String, dynamic>,
        builder: (context, data, reload) {
          final teachers = data['teachers'] as List;
          final hours = Map<String, dynamic>.from(data['hours'] as Map);
          final open_ = data['open_now'] == true;

          if (data['chat_enabled'] != true) {
            return const EmptyState(icon: Icons.speaker_notes_off_rounded, title: 'Chat is switched off by the school');
          }
          if (teachers.isEmpty) {
            return const EmptyState(icon: Icons.forum_outlined, title: 'No teacher to message yet', subtitle: 'Teachers appear here once the school assigns them to your child\'s class.');
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
            children: [
              Panel(
                color: (open_ ? AppColors.green : AppColors.amber).withValues(alpha: 0.1),
                borderColor: Colors.transparent,
                child: Row(children: [
                  Icon(open_ ? Icons.check_circle_rounded : Icons.schedule_rounded, color: open_ ? AppColors.green : AppColors.amber),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Teachers can be messaged between ${niceTime(hours['from'] as String?)} and ${niceTime(hours['to'] as String?)}.', style: const TextStyle(fontWeight: FontWeight.w600))),
                ]),
              ),
              const SizedBox(height: 12),
              for (final t in teachers)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Builder(builder: (context) {
                    final teacher = Map<String, dynamic>.from(t as Map);
                    final unread = teacher['unread'] as int? ?? 0;
                    return Panel(
                      onTap: () async {
                        await Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => ConversationScreen(
                            title: teacher['name'] as String,
                            subtitle: 'About ${child['name']}',
                            path: '/children/$childId/chat/${teacher['user_id']}/messages',
                            notice: open_ ? null : 'It is outside chat hours. You can send messages between ${niceTime(hours['from'] as String?)} and ${niceTime(hours['to'] as String?)}.',
                          ),
                        ));
                        reload();
                      },
                      child: Row(
                        children: [
                          Avatar(name: teacher['name'] as String),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(teacher['name'] as String, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                                Text((teacher['designation'] as String?) ?? 'Teacher', style: const TextStyle(color: AppColors.soft, fontSize: 13)),
                              ],
                            ),
                          ),
                          if (unread > 0) Pill('$unread new', color: AppColors.red, solid: true) else const Icon(Icons.chevron_right_rounded, color: AppColors.soft),
                        ],
                      ),
                    );
                  }),
                ),
            ],
          );
        },
      ),
    );
  }
}
