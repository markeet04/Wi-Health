import 'auth_exceptions.dart';
import 'auth_models.dart';
import 'auth_service.dart';
import 'roles.dart';

/// In-memory auth backend for the frontend build. Behaves like the real
/// thing: latency, typed errors, seeded accounts, RBAC roles.
///
/// Demo accounts:
///   qasim@wihealth.app / demo123  — App User (seeded, 3 linked devices)
///   admin@wihealth.app / admin123 — Admin (mobile login is BLOCKED by RBAC)
///   any other valid email + password (6+ chars) auto-provisions an App User.
class MockAuthService implements AuthService {
  MockAuthService({this.latency = const Duration(milliseconds: 350)});

  final Duration latency;

  static final _emailRx = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.]+$');

  final Map<String, _MockAccount> _accounts = {
    'qasim@wihealth.app': _MockAccount(
      password: 'demo123',
      user: const AuthUser(
        uid: 'u-qasim',
        name: 'Qasim Majid',
        email: 'qasim@wihealth.app',
        role: UserRole.appUser,
        emailVerified: true,
        linkedDeviceIds: ['WH-S3-A1F4', 'WH-S3-B7C2', 'WH-S3-C9D8'],
      ),
    ),
    'admin@wihealth.app': _MockAccount(
      password: 'admin123',
      user: const AuthUser(
        uid: 'u-admin',
        name: 'Fleet Admin',
        email: 'admin@wihealth.app',
        role: UserRole.admin,
        emailVerified: true,
      ),
    ),
  };

  AuthUser? _session;

  @override
  Future<AuthUser?> restoreSession() async {
    await Future<void>.delayed(latency);
    return _session;
  }

  @override
  Future<AuthUser> signIn(
      {required String email, required String password}) async {
    await Future<void>.delayed(latency);
    final key = email.trim().toLowerCase();
    if (!_emailRx.hasMatch(key)) {
      throw const AuthException(AuthErrorCode.invalidEmail);
    }
    if (password.length < 6) {
      throw const AuthException(AuthErrorCode.wrongPassword);
    }

    final existing = _accounts[key];
    if (existing != null) {
      if (existing.password != password) {
        throw const AuthException(AuthErrorCode.wrongPassword);
      }
      return _session = existing.user;
    }

    // Demo convenience: unknown valid credentials auto-provision an
    // App User so anyone can try the app. Remove for production.
    final user = _provision(key, password, _nameFromEmail(key));
    return _session = user;
  }

  @override
  Future<AuthUser> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    await Future<void>.delayed(latency);
    final key = email.trim().toLowerCase();
    if (!_emailRx.hasMatch(key)) {
      throw const AuthException(AuthErrorCode.invalidEmail);
    }
    if (password.length < 6) {
      throw const AuthException(AuthErrorCode.weakPassword);
    }
    if (_accounts.containsKey(key)) {
      throw const AuthException(AuthErrorCode.emailInUse);
    }
    final user = _provision(key, password, name.trim());
    return _session = user;
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    await Future<void>.delayed(latency);
    if (!_emailRx.hasMatch(email.trim().toLowerCase())) {
      throw const AuthException(AuthErrorCode.invalidEmail);
    }
    // Mock: pretend the email went out. (Real impl: Firebase handles it.)
  }

  @override
  Future<void> signOut() async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    _session = null;
  }

  AuthUser _provision(String email, String password, String name) {
    final user = AuthUser(
      uid: 'u-${_accounts.length + 1}',
      name: name.isEmpty ? _nameFromEmail(email) : name,
      email: email,
      role: UserRole.appUser,
    );
    _accounts[email] = _MockAccount(password: password, user: user);
    return user;
  }

  static String _nameFromEmail(String email) {
    final raw = email.split('@').first.replaceAll(RegExp(r'[._+-]+'), ' ');
    return raw
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }
}

class _MockAccount {
  const _MockAccount({required this.password, required this.user});

  final String password;
  final AuthUser user;
}
