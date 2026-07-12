import 'auth_models.dart';
import 'auth_service.dart';

/// Firebase implementation slot — for the teammate wiring connectivity.
///
/// ── Setup checklist ────────────────────────────────────────────────────
/// 1. Create the (separate!) Wi-Health Firebase project; enable
///    Email/Password auth and Realtime Database.
/// 2. `flutter pub add firebase_core firebase_auth firebase_database`
///    then `flutterfire configure` (generates lib/firebase_options.dart).
/// 3. Drop google-services.json into android/app/ — it is gitignored on
///    purpose (contains API keys); get it from the team out-of-band.
/// 4. In main.dart:  await Firebase.initializeApp(options: ...);
/// 5. In auth_controller.dart swap MockAuthService() for
///    FirebaseAuthService().
/// 6. Deploy cloud/database.rules.json (`firebase deploy --only database`
///    from the cloud/ folder). Roles arrive as custom claims set by the
///    NestJS backend — see shared/contracts/auth-rbac.json.
///
/// ── Implementation guide (per method) ──────────────────────────────────
/// restoreSession:
///   final u = FirebaseAuth.instance.currentUser;
///   if (u == null) return null;
///   return _toAuthUser(u);   // includes claim fetch below
///
/// signIn:
///   try {
///     final cred = await FirebaseAuth.instance
///         .signInWithEmailAndPassword(email: email, password: password);
///     return _toAuthUser(cred.user!);
///   } on FirebaseAuthException catch (e) {
///     throw _mapError(e);    // invalid-email/user-not-found/wrong-password...
///   }
///
/// signUp:
///   final cred = await FirebaseAuth.instance
///       .createUserWithEmailAndPassword(email: email, password: password);
///   await cred.user!.updateDisplayName(name);
///   await cred.user!.sendEmailVerification();
///   // Role claim (app_user) is set by the backend onUserCreate hook;
///   // force-refresh the token so the claim is visible immediately:
///   await cred.user!.getIdToken(true);
///   return _toAuthUser(cred.user!);
///
/// _toAuthUser (role + linked devices):
///   final token = await user.getIdTokenResult();
///   final role = UserRole.fromClaim(token.claims?['role'] as String?);
///   final snap = await FirebaseDatabase.instance
///       .ref('users/${user.uid}/devices').get();
///   final deviceIds = snap.exists
///       ? `(snap.value as Map).keys.cast<String>().toList()`
///       : `const <String>[]`;
///   return AuthUser(uid: user.uid, name: user.displayName ?? '',
///       email: user.email ?? '', role: role,
///       emailVerified: user.emailVerified, linkedDeviceIds: deviceIds);
///
/// sendPasswordReset:
///   await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
///
/// signOut:
///   await FirebaseAuth.instance.signOut();
///
/// Error mapping → AuthException(AuthErrorCode.x):
///   invalid-email → invalidEmail · user-not-found → userNotFound
///   wrong-password / invalid-credential → wrongPassword
///   email-already-in-use → emailInUse · weak-password → weakPassword
///   network-request-failed → network · anything else → unknown
class FirebaseAuthService implements AuthService {
  static const _todo =
      'FirebaseAuthService is not wired yet — follow the checklist in '
      'lib/auth/firebase_auth_service.dart, then swap it in inside '
      'auth_controller.dart.';

  @override
  Future<AuthUser?> restoreSession() => throw UnimplementedError(_todo);

  @override
  Future<AuthUser> signIn({required String email, required String password}) =>
      throw UnimplementedError(_todo);

  @override
  Future<AuthUser> signUp({
    required String name,
    required String email,
    required String password,
  }) =>
      throw UnimplementedError(_todo);

  @override
  Future<void> sendPasswordReset(String email) =>
      throw UnimplementedError(_todo);

  @override
  Future<void> signOut() => throw UnimplementedError(_todo);
}
