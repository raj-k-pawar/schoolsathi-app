/// One app for everyone. After sign-in it opens in the mode that fits the login:
/// parent, teacher / office, bus driver - or gate scanner, which staff choose on a gate tablet.
/// A person with more than one role (a teacher who is also a parent) can switch in Profile.
enum AppKind { parent, teacher, driver, gate }

class AppConfig {
  /// Server address baked in at build time: --dart-define=API_URL=https://your-domain
  /// It can also be changed on the phone from the login screen (long-press the logo).
  static const String defaultApiUrl = String.fromEnvironment('API_URL', defaultValue: 'https://schoolsathi.nextlogic.in');

  static const String appName = 'SchoolSathi';

  static const String tagline = 'One app for parents, teachers and school staff';

  /// The mode the app is in now (set by the session after sign-in).
  static AppKind kind = AppKind.parent;

  static const _staff = ['teacher', 'school_admin', 'office_staff'];

  /// Modes a login can use, in the order they are offered.
  static List<AppKind> modesFor(List<String> roles) => [
        if (roles.any(_staff.contains)) AppKind.teacher,
        if (roles.contains('driver')) AppKind.driver,
        if (roles.contains('parent') || roles.contains('student')) AppKind.parent,
        if (roles.any(_staff.contains)) AppKind.gate,
      ];

  /// Mode to open in when the user has not chosen one: never the gate scanner.
  static AppKind defaultMode(List<String> roles) => modesFor(roles).firstWhere((m) => m != AppKind.gate, orElse: () => AppKind.parent);

  static String modeLabel(AppKind mode) => switch (mode) {
        AppKind.parent => 'Parent',
        AppKind.teacher => 'Teacher / office',
        AppKind.driver => 'Bus driver',
        AppKind.gate => 'Gate scanner',
      };

  static String modeHint(AppKind mode) => switch (mode) {
        AppKind.parent => 'Your children: attendance, bus, fees, homework',
        AppKind.teacher => 'Classes, attendance, homework, leave, messages',
        AppKind.driver => 'Bus trips, boarding scan, SOS',
        AppKind.gate => 'Full-screen ID-card scanner for the school gate',
      };
}
