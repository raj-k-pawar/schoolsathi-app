import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../parent/learning_screens.dart' show openAttachment;

class TeacherHomeworkScreen extends StatefulWidget {
  const TeacherHomeworkScreen({super.key});

  @override
  State<TeacherHomeworkScreen> createState() => _TeacherHomeworkScreenState();
}

class _TeacherHomeworkScreenState extends State<TeacherHomeworkScreen> {
  final _loader = GlobalKey<LoaderState<List<dynamic>>>();

  @override
  Widget build(BuildContext context) {
    final api = apiOf(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Homework'), automaticallyImplyLeading: false),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final posted = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const PostHomeworkScreen()));
          if (posted == true) _loader.currentState?.reload();
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('Post homework'),
      ),
      body: Loader<List<dynamic>>(
        key: _loader,
        load: () async => ((await api.get('/teacher/homework')) as Map<String, dynamic>)['homework'] as List<dynamic>,
        builder: (context, items, _) {
          if (items.isEmpty) return const EmptyState(icon: Icons.menu_book_rounded, title: 'No homework posted yet', subtitle: 'Tap "Post homework" to send work to a class.');
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final hw = Map<String, dynamic>.from(items[i] as Map);
              return Panel(
                onTap: () => open(context, SubmissionsScreen(homework: hw)),
                child: Row(children: [
                  const IconBadge(Icons.menu_book_rounded),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(hw['title'] as String, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                      Text('Class ${hw['class']} - ${hw['subject'] ?? 'General'}${hw['due_date'] != null ? ' - due ${niceDate(hw['due_date'] as String, pattern: 'd MMM')}' : ''}', style: const TextStyle(color: AppColors.soft, fontSize: 13)),
                    ]),
                  ),
                  Pill('${hw['submissions']} in', color: AppColors.blue),
                ]),
              );
            },
          );
        },
      ),
    );
  }
}

class PostHomeworkScreen extends StatefulWidget {
  const PostHomeworkScreen({super.key});

  @override
  State<PostHomeworkScreen> createState() => _PostHomeworkScreenState();
}

class _PostHomeworkScreenState extends State<PostHomeworkScreen> {
  final _title = TextEditingController();
  final _details = TextEditingController();
  final _picker = ImagePicker();
  final List<XFile> _photos = [];
  List<dynamic>? _sections;
  List<dynamic> _subjects = const [];
  int? _sectionId;
  int? _subjectId;
  DateTime? _due;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _details.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final api = apiOf(context);
      final sections = ((await api.get('/teacher/sections')) as Map<String, dynamic>)['sections'] as List;
      final subjects = ((await api.get('/teacher/subjects')) as Map<String, dynamic>)['subjects'] as List;
      if (!mounted) return;
      setState(() {
        _sections = sections;
        _subjects = subjects;
        if (sections.length == 1) _sectionId = (sections.first as Map)['id'] as int;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _addPhoto(ImageSource source) async {
    try {
      final photo = await _picker.pickImage(source: source, imageQuality: 70, maxWidth: 1800);
      if (photo != null && _photos.length < 5) setState(() => _photos.add(photo));
    } catch (_) {
      if (mounted) toast(context, 'Could not open the camera or gallery. Please allow the permission.', error: true);
    }
  }

  Future<void> _post() async {
    if (_sectionId == null || _title.text.trim().isEmpty) {
      toast(context, 'Choose a class and write a title.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final files = <UploadFile>[];
      for (final photo in _photos) {
        files.add(UploadFile('files[]', photo.name, await photo.readAsBytes()));
      }
      if (!mounted) return;
      await apiOf(context).upload('/teacher/homework', fields: {
        'section_id': '$_sectionId',
        if (_subjectId != null) 'subject_id': '$_subjectId',
        'title': _title.text.trim(),
        'description': _details.text.trim(),
        if (_due != null) 'due_date': DateFormat('yyyy-MM-dd').format(_due!),
      }, files: files);
      if (!mounted) return;
      toast(context, 'Homework posted. Parents can see it now.');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return AppPage(title: 'Post homework', body: EmptyState(icon: Icons.cloud_off_rounded, title: _error!, action: 'Retry', onAction: _load));
    if (_sections == null) return const AppPage(title: 'Post homework', body: Center(child: CircularProgressIndicator()));

    return AppPage(
      title: 'Post homework',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          DropdownButtonFormField<int>(
            initialValue: _sectionId,
            decoration: const InputDecoration(labelText: 'Class'),
            items: [for (final s in _sections!) DropdownMenuItem(value: (s as Map)['id'] as int, child: Text('Class ${s['name']}'))],
            onChanged: (value) => setState(() => _sectionId = value),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int?>(
            initialValue: _subjectId,
            decoration: const InputDecoration(labelText: 'Subject'),
            items: [const DropdownMenuItem<int?>(value: null, child: Text('General')), for (final s in _subjects) DropdownMenuItem<int?>(value: (s as Map)['id'] as int, child: Text(s['name'] as String))],
            onChanged: (value) => setState(() => _subjectId = value),
          ),
          const SizedBox(height: 12),
          TextField(controller: _title, maxLength: 200, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Title', hintText: 'Chapter 4, exercise 2', counterText: '')),
          const SizedBox(height: 12),
          TextField(controller: _details, maxLines: 4, maxLength: 5000, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Details', alignLabelWithHint: true, counterText: '')),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final today = DateUtils.dateOnly(DateTime.now());
              final picked = await showDatePicker(context: context, initialDate: _due ?? today.add(const Duration(days: 1)), firstDate: today, lastDate: today.add(const Duration(days: 120)));
              if (picked != null) setState(() => _due = picked);
            },
            icon: const Icon(Icons.event_rounded),
            label: Text(_due == null ? 'Due date (optional)' : 'Due ${DateFormat('EEE, d MMM').format(_due!)}'),
          ),
          const SizedBox(height: 12),
          if (_photos.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Wrap(spacing: 8, children: [for (var i = 0; i < _photos.length; i++) Chip(label: Text('Photo ${i + 1}'), onDeleted: () => setState(() => _photos.removeAt(i)))]),
            ),
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: () => _addPhoto(ImageSource.camera), icon: const Icon(Icons.photo_camera_rounded), label: const Text('Camera'))),
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton.icon(onPressed: () => _addPhoto(ImageSource.gallery), icon: const Icon(Icons.photo_library_rounded), label: const Text('Gallery'))),
          ]),
          const SizedBox(height: 20),
          FilledButton(onPressed: _busy ? null : _post, child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : const Text('Post to class')),
        ],
      ),
    );
  }
}

class SubmissionsScreen extends StatefulWidget {
  const SubmissionsScreen({super.key, required this.homework});

  final Map<String, dynamic> homework;

  @override
  State<SubmissionsScreen> createState() => _SubmissionsScreenState();
}

class _SubmissionsScreenState extends State<SubmissionsScreen> {
  final _loader = GlobalKey<LoaderState<List<dynamic>>>();

  Future<void> _check(Map<String, dynamic> submission) async {
    final remark = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Mark ${submission['student']} as checked'),
        content: TextField(controller: remark, maxLength: 255, decoration: const InputDecoration(labelText: 'Remark (optional)', counterText: '')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(110, 44)), onPressed: () => Navigator.pop(context, true), child: const Text('Checked')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final done = await guard(context, () => apiOf(context).put('/teacher/submissions/${submission['id']}', {'teacher_remark': remark.text.trim()}));
    if (done != null) _loader.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final api = apiOf(context);
    final hw = widget.homework;

    return AppPage(
      title: hw['title'] as String,
      body: Loader<List<dynamic>>(
        key: _loader,
        load: () async => ((await api.get('/teacher/homework/${hw['id']}/submissions')) as Map<String, dynamic>)['submissions'] as List<dynamic>,
        builder: (context, submissions, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
            children: [
              Panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Class ${hw['class']} - ${hw['subject'] ?? 'General'}', style: const TextStyle(color: AppColors.soft)),
                  if ((hw['description'] as String?)?.isNotEmpty ?? false) Padding(padding: const EdgeInsets.only(top: 8), child: Text(hw['description'] as String, style: const TextStyle(height: 1.45))),
                ]),
              ),
              SectionTitle('Submissions (${submissions.length})'),
              if (submissions.isEmpty) const Panel(child: Text('No student has submitted yet.', style: TextStyle(color: AppColors.soft))),
              for (final s in submissions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Builder(builder: (context) {
                    final submission = Map<String, dynamic>.from(s as Map);
                    final checked = submission['status'] == 'checked';
                    return Panel(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text('${submission['student']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5))),
                          Pill(checked ? 'Checked' : 'To check', color: checked ? AppColors.green : AppColors.amber),
                        ]),
                        if ((submission['note'] as String?)?.isNotEmpty ?? false) Padding(padding: const EdgeInsets.only(top: 6), child: Text(submission['note'] as String)),
                        Wrap(spacing: 8, children: [
                          for (final file in submission['attachments'] as List)
                            ActionChip(avatar: const Icon(Icons.image_rounded, size: 18), label: Text((file as Map)['name'] as String, overflow: TextOverflow.ellipsis), onPressed: () => openAttachment(context, file['url'] as String, file['name'] as String)),
                        ]),
                        if (!checked) Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: () => _check(submission), icon: const Icon(Icons.check_circle_outline_rounded), label: const Text('Mark checked'))),
                      ]),
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
