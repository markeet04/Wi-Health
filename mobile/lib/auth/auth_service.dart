import 'auth_models.dart';

/// Authentication backend interface. Screens and the AuthController only
/// ever see this — swapping MockAuthService for FirebaseAuthService (or a
/// NestJS-token flow) requires changing one line in auth_controller.dart.
abstract class AuthService {
  /// Currently signed-in user, or null. Implementations should restore
  /// persisted sessions here (Firebase does this automatically).
  Future<AuthUser?> restoreSession();

  /// Signs in with email + password. Throws [AuthException] on failure.
  /// Returns the authenticated user WITH its role resolved (custom claim).
  Future<AuthUser> signIn({required String email, required String password});

  /// Registers a new App User account. Throws [AuthException] on failure.
  /// Role defaults to app_user — roles are only ever elevated server-side.
  Future<AuthUser> signUp({
    required String name,
    required String email,
    required String password,
  });

  /// Sends a password-reset email. Throws [AuthException] on failure.
  Future<void> sendPasswordReset(String email);

  /// Re-sends the account's verification email. The app signs the user back
  /// out the moment it detects an unverified email (see
  /// AuthController.login), so this re-authenticates with the given
  /// credentials to get a valid session just long enough to trigger the
  /// email, then signs out again. Throws [AuthException] on failure.
  Future<void> resendVerificationEmail(
      {required String email, required String password});

  Future<void> signOut();
}
