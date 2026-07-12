import 'roles.dart';

/// Authenticated identity as the app sees it — independent of whether it
/// came from the mock service or Firebase.
class AuthUser {
  const AuthUser({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    this.emailVerified = false,
    this.linkedDeviceIds = const [],
  });

  final String uid;
  final String name;
  final String email;
  final UserRole role;
  final bool emailVerified;

  /// Devices linked to this account (/users/$uid/devices keys) — drives
  /// the multi-patient switcher once real data is wired.
  final List<String> linkedDeviceIds;

  bool can(Permission permission) => role.can(permission);

  AuthUser copyWith({String? name, bool? emailVerified}) => AuthUser(
        uid: uid,
        name: name ?? this.name,
        email: email,
        role: role,
        emailVerified: emailVerified ?? this.emailVerified,
        linkedDeviceIds: linkedDeviceIds,
      );
}
