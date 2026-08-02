import 'package:flutter/material.dart';
import '../auth/auth_controller.dart';
import '../auth/roles.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'auth/login_screen.dart';
import 'link_device_screen.dart';
import 'devices_screen.dart';
import 'settings_screen.dart';
import 'support_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Profile', style: WiText.h1),
              const SizedBox(height: 18),
              SoftCard(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: const BoxDecoration(
                              color: WiColors.primarySoft, shape: BoxShape.circle),
                          alignment: Alignment.center,
                          child: Text(
                            app.userName
                                .split(' ')
                                .take(2)
                                .map((w) => w[0])
                                .join(),
                            style: const TextStyle(
                                color: WiColors.primaryDeep,
                                fontWeight: FontWeight.w800,
                                fontSize: 17),
                          ),
                        ),
                        Positioned(
                          right: -1,
                          bottom: -1,
                          child: Container(
                            width: 15,
                            height: 15,
                            decoration: BoxDecoration(
                              color: WiColors.green,
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: Colors.white, width: 2.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(app.userName,
                              style: WiText.title.copyWith(fontSize: 16)),
                          const SizedBox(height: 2),
                          Text(app.userEmail, style: WiText.caption),
                          const SizedBox(height: 6),
                          StatusPill(
                            text:
                                'Caregiver · ${app.patients.length} patients',
                            color: WiColors.primary,
                            background: WiColors.primarySoft,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              _sectionLabel('ACCOUNT'),
              SoftCard(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: Column(
                  children: [
                    ListRow(
                      icon: Icons.person_outline_rounded,
                      iconColor: WiColors.primary,
                      iconBackground: WiColors.primarySoft,
                      title: 'Personal Information',
                      onTap: () => _personalInfoSheet(context),
                    ),
                    const Divider(height: 1, indent: 52),
                    ListRow(
                      icon: Icons.shield_outlined,
                      iconColor: WiColors.blue,
                      iconBackground: WiColors.blueSoft,
                      title: 'Security & Sessions',
                      onTap: () => _securitySheet(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _sectionLabel('DEVICES'),
              SoftCard(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: Column(
                  children: [
                    ListRow(
                      icon: Icons.sensors_rounded,
                      iconColor: WiColors.primary,
                      iconBackground: WiColors.primarySoft,
                      title: 'My Devices',
                      subtitle:
                          '${app.patients.where((p) => p.online).length} of ${app.patients.length} online',
                      onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => DevicesScreen(app: app))),
                    ),
                    const Divider(height: 1, indent: 52),
                    ListRow(
                      icon: Icons.add_circle_outline_rounded,
                      iconColor: WiColors.violet,
                      iconBackground: WiColors.violetSoft,
                      title: 'Request a Device',
                      subtitle: 'Ask your admin to assign a device',
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => LinkDeviceScreen(app: app))),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _sectionLabel('SUPPORT'),
              SoftCard(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: Column(
                  children: [
                    // RBAC-gated: only roles with submitComplaint see this
                    // (App Users do; kept explicit so the pattern is visible).
                    if (authController.user
                            ?.can(Permission.submitComplaint) ??
                        true) ...[
                      ListRow(
                        icon: Icons.support_agent_rounded,
                        iconColor: WiColors.amber,
                        iconBackground: WiColors.amberSoft,
                        title: 'Complaints & Support',
                        subtitle:
                            '${app.complaints.length} previous requests',
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => SupportScreen(app: app))),
                      ),
                      const Divider(height: 1, indent: 52),
                    ],
                    ListRow(
                      icon: Icons.notifications_active_outlined,
                      iconColor: WiColors.blue,
                      iconBackground: WiColors.blueSoft,
                      title: 'Notifications',
                      onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => SettingsScreen(app: app))),
                    ),
                    const Divider(height: 1, indent: 52),
                    ListRow(
                      icon: Icons.settings_outlined,
                      iconColor: WiColors.inkSoft,
                      iconBackground: WiColors.field,
                      title: 'App Settings',
                      onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => SettingsScreen(app: app))),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SoftCard(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: ListRow(
                  icon: Icons.logout_rounded,
                  iconColor: WiColors.red,
                  iconBackground: WiColors.redSoft,
                  title: 'Log Out',
                  titleColor: WiColors.red,
                  trailing: const SizedBox.shrink(),
                  onTap: () async {
                    await authController.logout();
                    if (context.mounted) {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(
                            builder: (_) => const LoginScreen()),
                        (route) => false,
                      );
                    }
                  },
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child:
                    Text('Wi-Health · prototype v0.1.0', style: WiText.caption),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(left: 6, bottom: 10),
        child: Text(text, style: WiText.label),
      );

  // Read-only account details drawn from the signed-in AuthUser + AppState.
  void _personalInfoSheet(BuildContext context) {
    final user = authController.user;
    _infoSheet(
      context,
      title: 'Personal Information',
      subtitle: 'Details from your Wi-Health account.',
      rows: [
        ('Name', user?.name ?? app.userName),
        ('Email', user?.email ?? app.userEmail),
        ('Role', user?.role == UserRole.admin ? 'Admin' : 'App User'),
        ('Patients linked', '${app.patients.length}'),
      ],
    );
  }

  void _securitySheet(BuildContext context) {
    final user = authController.user;
    _infoSheet(
      context,
      title: 'Security & Sessions',
      subtitle: 'This device is signed in to the account below.',
      rows: [
        ('Signed in as', user?.email ?? app.userEmail),
        ('Email verified', (user?.emailVerified ?? false) ? 'Yes' : 'No'),
        ('Account ID', user?.uid ?? app.userId),
        ('Session', 'Active on this device'),
      ],
    );
  }

  void _infoSheet(
    BuildContext context, {
    required String title,
    required String subtitle,
    required List<(String, String)> rows,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: WiColors.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 34),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                    color: WiColors.line,
                    borderRadius: BorderRadius.circular(4)),
              ),
            ),
            const SizedBox(height: 20),
            Text(title, style: WiText.h2),
            const SizedBox(height: 6),
            Text(subtitle, style: WiText.body),
            const SizedBox(height: 18),
            for (final (label, value) in rows) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 130, child: Text(label, style: WiText.body)),
                    Expanded(
                      child: Text(value,
                          style: WiText.title.copyWith(fontSize: 13),
                          textAlign: TextAlign.right),
                    ),
                  ],
                ),
              ),
              if ((label, value) != rows.last) const Divider(height: 1),
            ],
          ],
        ),
      ),
    );
  }

}
