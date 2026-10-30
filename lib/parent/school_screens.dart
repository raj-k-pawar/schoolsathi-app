import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

class CalendarScreen extends StatelessWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final api = apiOf(context);

    return AppPage(
      title: tr('Calendar'),
      body: Loader<List<dynamic>>(
        load: () async => ((await api.get('/calendar')) as Map<String, dynamic>)['events'] as List<dynamic>,
        builder: (context, events, _) {
          if (events.isEmpty) return EmptyState(icon: Icons.event_rounded, title: tr('Nothing here yet'), subtitle: 'Holidays, events and exams appear here.');
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
            itemCount: events.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final event = Map<String, dynamic>.from(events[i] as Map);
              final (label, color, icon) = switch (event['type']) {
                'holiday' => ('Holiday', AppColors.green, Icons.beach_access_rounded),
                'exam' => ('Exam', AppColors.red, Icons.edit_note_rounded),
                _ => ('Event', AppColors.blue, Icons.celebration_rounded),
              };
              final start = DateTime.parse(event['start_date'] as String);
              final same = event['start_date'] == event['end_date'];
              return Panel(
                child: Row(children: [
                  Container(
                    width: 58,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16)),
                    child: Column(children: [
                      Text('${start.day}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
                      Text(niceDate(event['start_date'] as String, pattern: 'MMM').toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color)),
                    ]),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(event['title'] as String, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                      if (!same) Text('till ${niceDate(event['end_date'] as String)}', style: const TextStyle(color: AppColors.soft, fontSize: 13)),
                      const SizedBox(height: 6),
                      Pill(label, color: color, icon: icon),
                    ]),
                  ),
                ]),
              );
            },
          );
        },
      ),
    );
  }
}

class GalleryScreen extends StatelessWidget {
  const GalleryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final api = apiOf(context);

    return AppPage(
      title: tr('Gallery'),
      body: Loader<List<dynamic>>(
        load: () async => ((await api.get('/gallery')) as Map<String, dynamic>)['albums'] as List<dynamic>,
        builder: (context, albums, _) {
          if (albums.isEmpty) return EmptyState(icon: Icons.photo_library_rounded, title: tr('Nothing here yet'), subtitle: 'Photos of school events appear here.');
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
            children: [
              for (final a in albums) ...[
                Builder(builder: (context) {
                  final album = Map<String, dynamic>.from(a as Map);
                  final photos = List<String>.from(album['photos'] as List);
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SectionTitle('${album['title']}${album['event_date'] != null ? '  -  ${niceDate(album['event_date'] as String)}' : ''}'),
                    if (photos.isEmpty) const Text('No photos yet.', style: TextStyle(color: AppColors.soft)),
                    GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      children: [
                        for (final url in photos)
                          GestureDetector(
                            onTap: () => open(context, _PhotoView(url: url)),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Image.network(url, headers: apiOf(context).authHeaders, fit: BoxFit.cover, errorBuilder: (_, _, _) => Container(color: AppColors.line, child: const Icon(Icons.broken_image_outlined, color: AppColors.soft))),
                            ),
                          ),
                      ],
                    ),
                  ]);
                }),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _PhotoView extends StatelessWidget {
  const _PhotoView({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: Center(child: InteractiveViewer(child: Image.network(url, headers: apiOf(context).authHeaders))),
    );
  }
}

/// DPDP consent: the parent decides, per child, what the school may use.
class ConsentScreen extends StatefulWidget {
  const ConsentScreen({super.key, required this.child});

  final Map<String, dynamic> child;

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  final _loader = GlobalKey<LoaderState<List<dynamic>>>();

  static const _help = {
    'data': 'Attendance, fees, homework and marks of your child in this app.',
    'face': 'Mark attendance by recognising your child\'s face at the gate. If you say no, the ID card is used instead.',
    'location': 'Show you where the school bus is during a trip.',
  };

  Future<void> _set(String type, bool granted) async {
    final ok = await guard(context, () => apiOf(context).put('/children/${widget.child['id']}/consents', {'type': type, 'granted': granted}));
    if (ok != null) _loader.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final api = apiOf(context);

    return AppPage(
      title: tr('Privacy and consent'),
      body: Loader<List<dynamic>>(
        key: _loader,
        load: () async => ((await api.get('/children/${widget.child['id']}/consents')) as Map<String, dynamic>)['consents'] as List<dynamic>,
        builder: (context, consents, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          children: [
            Text('For ${widget.child['name']}. You can change your choice at any time.', style: const TextStyle(color: AppColors.soft)),
            const SizedBox(height: 12),
            for (final c in consents)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Builder(builder: (context) {
                  final consent = Map<String, dynamic>.from(c as Map);
                  final granted = consent['granted'] as bool?;
                  return Panel(
                    padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: granted == true,
                      onChanged: (value) => _set(consent['type'] as String, value),
                      title: Text(consent['label'] as String, style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text('${_help[consent['type']] ?? ''}${granted == null ? '\nNot answered yet.' : ''}'),
                    ),
                  );
                }),
              ),
          ],
        ),
      ),
    );
  }
}
