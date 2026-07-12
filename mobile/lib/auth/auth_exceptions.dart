/// Typed auth failures with user-presentable messages. The Firebase
/// implementation maps FirebaseAuthException codes onto these, so screens
/// never need to know which backend is active.
enum AuthErrorCode {
  invalidEmail,
  userNotFound,
  wrongPassword,
  emailInUse,
  weakPassword,
  passwordMismatch,
  emptyFields,
  roleNotAllowed,
  network,
  unknown,
}

class AuthException implements Exception {
  const AuthException(this.code, [String? message])
      : _message = message;

  final AuthErrorCode code;
  final String? _message;

  String get message => _message ?? defaultMessageFor(code);

  static String defaultMessageFor(AuthErrorCode code) => switch (code) {
        AuthErrorCode.invalidEmail => 'That email address doesn’t look right.',
        AuthErrorCode.userNotFound => 'No account found for that email.',
        AuthErrorCode.wrongPassword => 'Incorrect email or password.',
        AuthErrorCode.emailInUse =>
          'An account with that email already exists.',
        AuthErrorCode.weakPassword =>
          'Password must be at least 6 characters.',
        AuthErrorCode.passwordMismatch => 'Passwords don’t match.',
        AuthErrorCode.emptyFields => 'Please fill in all the fields.',
        AuthErrorCode.roleNotAllowed =>
          'Admin accounts sign in on the web admin panel, not the mobile app.',
        AuthErrorCode.network =>
          'Couldn’t reach the server — check your connection.',
        AuthErrorCode.unknown => 'Something went wrong. Please try again.',
      };

  @override
  String toString() => 'AuthException(${code.name}): $message';
}
