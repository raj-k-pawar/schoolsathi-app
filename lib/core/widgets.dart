import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'api.dart';
import 'i18n.dart';
import 'session.dart';
import 'theme.dart';

String money(num? amount) => 'Rs ${NumberFormat('#,##,##0.##', 'en_IN').format(amount ?? 0)}';

String niceDate(String? iso, {String pattern = 'd MMM yyyy'}) {
  if (iso == null || iso.isEmpty) return '-';
  final date = DateTime.tryParse(iso);
  return date == null ? iso : DateFormat(pattern).format(date.toLocal());
}

String niceTime(String? hhmm) {
  if (hhmm == null || hhmm.length < 5) return '';
  final parts = hhmm.split(':');
  final time = DateTime(2000, 1, 1, int.tryParse(parts[0]) ?? 0, int.tryParse(parts[1]) ?? 0);
  return DateFormat('h:mm a').format(time);
}

void toast(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), backgroundColor: error ? AppColors.red : AppColors.ink));
}

/// Runs an API call for a button press and shows any error as a message.
Future<T?> guard<T>(BuildContext context, Future<T> Function() action) async {
  try {
    return await action();
  } on ApiException catch (e) {
    if (context.mounted) toast(context, e.message, error: true);
    return null;
  }
}

ApiClient apiOf(BuildContext context) => context.read<Session>().api;

/// Loads data, shows a spinner / error with retry / the content, and supports pull-to-refresh.
class Loader<T> extends StatefulWidget {
  const Loader({super.key, required this.load, required this.builder, this.padding});

  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;
  final EdgeInsets? padding;

  @override
  State<Loader<T>> createState() => LoaderState<T>();
}

class LoaderState<T> extends State<Loader<T>> {
  T? _data;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    if (mounted && _data == null) setState(() => _loading = true);
    try {
      final data = await widget.load();
      if (!mounted) return;
      setState(() {
        _data = data;
        _error = null;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Something went wrong. Please try again.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _data == null) {
      return const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()));
    }
    if (_data == null) {
      return EmptyState(icon: Icons.cloud_off_rounded, title: _error ?? 'Could not load', action: tr('Retry'), onAction: reload);
    }
    return RefreshIndicator(onRefresh: reload, child: widget.builder(context, _data as T, reload));
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.subtitle, this.action, this.onAction});

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final brand = Brand.current;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight.isFinite ? constraints.maxHeight : 300),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(color: brand.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
                    child: Icon(icon, size: 40, color: brand.primary),
                  ),
                  const SizedBox(height: 18),
                  Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 6),
                    Text(subtitle!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.soft, height: 1.4)),
                  ],
                  if (action != null) ...[
                    const SizedBox(height: 18),
                    FilledButton.tonal(onPressed: onAction, style: FilledButton.styleFrom(minimumSize: const Size(160, 48)), child: Text(action!)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// White rounded card used everywhere.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.onLongPress, this.color, this.gradient, this.borderColor});

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? color;
  final Gradient? gradient;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: gradient == null ? (color ?? Colors.white) : null,
          gradient: gradient,
          borderRadius: BorderRadius.circular(20),
          border: gradient == null ? Border.all(color: borderColor ?? AppColors.line) : null,
          boxShadow: [BoxShadow(color: const Color(0xFF102060).withValues(alpha: gradient == null ? 0.04 : 0.22), blurRadius: gradient == null ? 12 : 24, offset: const Offset(0, 8))],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, this.color = AppColors.blue, this.icon, this.solid = false});

  final String label;
  final Color color;
  final IconData? icon;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: solid ? color : color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: solid ? Colors.white : color), const SizedBox(width: 4)],
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: TextStyle(color: solid ? Colors.white : color, fontSize: 12, fontWeight: FontWeight.w800))),
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
      child: Row(
        children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
          if (action != null) InkWell(onTap: onAction, child: Text(action!, style: TextStyle(color: Brand.current.primary, fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }
}

/// Round icon on a tinted background.
class IconBadge extends StatelessWidget {
  const IconBadge(this.icon, {super.key, this.color, this.size = 44});

  final IconData icon;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Brand.current.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(size * 0.32)),
      child: Icon(icon, color: c, size: size * 0.52),
    );
  }
}

/// Initials in a coloured circle, or the photo when there is one.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, this.photoUrl, this.radius = 22});

  final String name;
  final String? photoUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final brand = Brand.current;
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final fallback = Container(
      width: radius * 2,
      height: radius * 2,
      alignment: Alignment.center,
      decoration: BoxDecoration(gradient: brand.gradient, shape: BoxShape.circle),
      child: Text(initial, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: radius * 0.85)),
    );
    if (photoUrl == null) return fallback;
    return ClipOval(
      child: Image.network(
        photoUrl!,
        headers: apiOf(context).authHeaders,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

/// Banner shown while requests are waiting for internet.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, required this.pending, this.onRetry});

  final int pending;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (pending == 0) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: AppColors.amber.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          const Icon(Icons.cloud_upload_outlined, color: Color(0xFF8A5A00)),
          const SizedBox(width: 10),
          Expanded(child: Text('$pending saved on this phone. They will be sent when internet is back.', style: const TextStyle(color: Color(0xFF8A5A00), fontWeight: FontWeight.w600, fontSize: 13))),
          if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('Send now')),
        ],
      ),
    );
  }
}

/// Curved gradient header used at the top of home screens.
class GradientHeader extends StatelessWidget {
  const GradientHeader({super.key, required this.child, this.bottom = 28});

  final Widget child;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final brand = Brand.current;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [brand.dark, Color.lerp(brand.dark, brand.primary, 0.7)!, brand.secondary]),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(padding: EdgeInsets.fromLTRB(20, 14, 20, bottom), child: child),
      ),
    );
  }
}

/// A plain page with a back arrow and title.
class AppPage extends StatelessWidget {
  const AppPage({super.key, required this.title, required this.body, this.actions, this.fab, this.bottom});

  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? fab;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: actions),
      body: SafeArea(top: false, child: body),
      floatingActionButton: fab,
      bottomNavigationBar: bottom,
    );
  }
}

void open(BuildContext context, Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
