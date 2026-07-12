import 'package:flutter/foundation.dart';
import 'auth_exceptions.dart';
import 'auth_models.dart';
import 'auth_service.dart';
import 'mock_auth_service.dart';
import 'roles.dart';

/// Session state for the whole app. Screens listen to this and call its
/// intents; it owns the AuthService and enforces the mobile RBAC policy
/// (App User surface only — admins are bounced to the web panel).
class AuthController extends ChangeNotifier {
  AuthController(this._service);

  final AuthService _service;

  AuthUser? _user;
  bool _busy = false;
  String? _error;

  AuthUser? get user => _user;
  bool get busy => _busy;
  String? get error => _error;
  bool get isAuthenticated => _user != null;

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  /// Restores a persisted session (splash calls this). Applies the same
  /// RBAC gate as login so a stale admin session can't slip through.
  Future<bool> restoreSession() async {
    final restored = await _service.restoreSession();
    if (restored == null) return false;
    if (!restored.role.mayUseMobileApp) {
      await _service.signOut();
      return false;
    }
    _user = restored;
    notifyListeners();
    return true;
  }

  Future<bool> login(String email, String password) => _run(() async {
        if (email.trim().isEmpty || password.isEmpty) {
          throw const AuthException(AuthErrorCode.emptyFields);
        }
        final user =
            await _service.signIn(email: email, password: password);
        _requireMobileAccess(user);
        _user = user;
      });

  Future<bool> signup({
    required String name,
    required String email,
    required String password,
    required String confirmPassword,
  }) =>
      _run(() async {
        if (name.trim().isEmpty || email.trim().isEmpty || password.isEmpty) {
          throw const AuthException(AuthErrorCode.emptyFields);
        }
        if (password != confirmPassword) {
          throw const AuthException(AuthErrorCode.passwordMismatch);
        }
        final user = await _service.signUp(
            name: name, email: email, password: password);
        _requireMobileAccess(user);
        _user = user;
      });

  Future<bool> sendPasswordReset(String email) => _run(() async {
        if (email.trim().isEmpty) {
          throw const AuthException(AuthErrorCode.emptyFields);
        }
        await _service.sendPasswordReset(email);
      });

  Future<void> logout() async {
    await _service.signOut();
    _user = null;
    _error = null;
    notifyListeners();
  }

  /// RBAC gate: the mobile app is the App User surface. This is UX only —
  /// the real enforcement is the Firebase rules / backend, which give an
  /// admin token no readable mobile data paths anyway.
  void _requireMobileAccess(AuthUser user) {
    if (!user.role.mayUseMobileApp) {
      _service.signOut();
      throw const AuthException(AuthErrorCode.roleNotAllowed);
    }
  }

  Future<bool> _run(Future<void> Function() action) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await action();
      return true;
    } on AuthException catch (e) {
      _error = e.message;
      return false;
    } catch (_) {
      _error = AuthException.defaultMessageFor(AuthErrorCode.unknown);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}

/// App-wide instance. To go live, swap MockAuthService for
/// FirebaseAuthService() — see lib/auth/firebase_auth_service.dart.
final AuthController authController = AuthController(MockAuthService());
