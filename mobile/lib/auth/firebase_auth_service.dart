import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_database/firebase_database.dart';

import 'auth_exceptions.dart';
import 'auth_models.dart';
import 'auth_service.dart';
import 'roles.dart';

/// Real Firebase implementation of [AuthService].
///
/// Activated by setting AppConfig.useFirebase = true once
/// `flutterfire configure` has generated lib/firebase_options.dart and the
/// rules in cloud/database.rules.json are deployed.
///
/// Role resolution (RBAC): custom claims (`role`) are authoritative when
/// present — the NestJS backend will set them later. Until that backend
/// exists, the role is read from /users/$uid/role, which the rules only
/// allow to be self-created as 'app_user' (no self-elevation path). Admins
/// are promoted by editing that node + claims server-side, never from a
/// client.
class FirebaseAuthService implements AuthService {
  FirebaseAuthService({fb.FirebaseAuth? auth, FirebaseDatabase? database})
      : _auth = auth ?? fb.FirebaseAuth.instance,
        _db = database ?? FirebaseDatabase.instance;

  final fb.FirebaseAuth _auth;
  final FirebaseDatabase _db;

  @override
  Future<AuthUser?> restoreSession() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    try {
      return await _toAuthUser(user);
    } catch (_) {
      // A broken/partial account state shouldn't wedge the splash screen.
      return null;
    }
  }

  @override
  Future<AuthUser> signIn(
      {required String email, required String password}) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
          email: email.trim(), password: password);
      return await _toAuthUser(cred.user!);
    } on fb.FirebaseAuthException catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<AuthUser> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
          email: email.trim(), password: password);
      final user = cred.user!;

      // The account now exists — everything below is best-effort so a
      // hiccup here can never fail the signup. The display name is set
      // again on next login via self-heal, the verification email can be
      // re-requested, and _toAuthUser re-provisions a missing user node.
      try {
        await user.updateDisplayName(name.trim());
        await user.sendEmailVerification();
        await _provisionUserNode(user,
            name: name.trim(), email: email.trim().toLowerCase());
      } catch (_) {
        // Recovered on next login by the self-heal in _toAuthUser.
      }

      return await _toAuthUser(user, displayNameOverride: name.trim());
    } on fb.FirebaseAuthException catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on fb.FirebaseAuthException catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  /// Creates the /users/$uid subtree. Written child-by-child on purpose:
  /// the rules grant self-writes on profile/role/settings individually,
  /// and a single parent-level set() would be denied (child permissions
  /// don't grant the parent write in RTDB).
  Future<void> _provisionUserNode(fb.User user,
      {required String name, required String email}) async {
    final base = _db.ref('users/${user.uid}');
    await base.child('profile').set({
      'name': name,
      'email': email,
      'createdAt': ServerValue.timestamp,
    });
    await base.child('role').set(UserRole.appUser.claim);
    await base.child('settings').set({
      'pushEnabled': true,
      'urgentOnly': false,
      'soundEnabled': true,
    });
  }

  Future<AuthUser> _toAuthUser(fb.User user,
      {String? displayNameOverride}) async {
    // Self-heal: an account whose signup was interrupted (or created
    // before provisioning worked) gets its /users node created on login.
    try {
      final profile = await _db.ref('users/${user.uid}/profile').get();
      if (!profile.exists) {
        await _provisionUserNode(
          user,
          name: displayNameOverride ??
              user.displayName ??
              MockNameFallback.fromEmail(user.email ?? ''),
          email: (user.email ?? '').toLowerCase(),
        );
      }
    } catch (_) {
      // Provisioning is best-effort here — never block a valid login.
    }

    // Custom claims win (future NestJS backend); DB role is the fallback.
    final token = await user.getIdTokenResult();
    var claim = token.claims?['role'] as String?;
    claim ??= (await _db.ref('users/${user.uid}/role').get()).value as String?;
    final role = UserRole.fromClaim(claim);

    var deviceIds = const <String>[];
    if (role == UserRole.appUser) {
      final snap = await _db.ref('users/${user.uid}/devices').get();
      if (snap.exists && snap.value is Map) {
        deviceIds = (snap.value as Map).keys.cast<String>().toList();
      }
    }

    return AuthUser(
      uid: user.uid,
      name: displayNameOverride ??
          user.displayName ??
          MockNameFallback.fromEmail(user.email ?? ''),
      email: user.email ?? '',
      role: role,
      emailVerified: user.emailVerified,
      linkedDeviceIds: deviceIds,
    );
  }

  AuthException _mapError(fb.FirebaseAuthException e) => switch (e.code) {
        'invalid-email' => const AuthException(AuthErrorCode.invalidEmail),
        'user-not-found' => const AuthException(AuthErrorCode.userNotFound),
        'wrong-password' ||
        'invalid-credential' ||
        'INVALID_LOGIN_CREDENTIALS' =>
          const AuthException(AuthErrorCode.wrongPassword),
        'email-already-in-use' =>
          const AuthException(AuthErrorCode.emailInUse),
        'weak-password' => const AuthException(AuthErrorCode.weakPassword),
        'network-request-failed' =>
          const AuthException(AuthErrorCode.network),
        _ => AuthException(AuthErrorCode.unknown, e.message),
      };
}

/// Tiny helper so a Firebase user without a display name still gets a
/// friendly one derived from their email.
class MockNameFallback {
  static String fromEmail(String email) {
    if (email.isEmpty) return 'Wi-Health User';
    final raw = email.split('@').first.replaceAll(RegExp(r'[._+-]+'), ' ');
    return raw
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }
}
