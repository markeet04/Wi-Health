/// Build-time switches for the app.
class AppConfig {
  AppConfig._();

  /// Master switch between the mock backend and real Firebase.
  ///
  /// Firebase is now the DEFAULT (the flip): the data layer, device
  /// assignment/requests, alerts, history and FCM are all wired to real
  /// Firebase, so a normal build uses live data.
  ///
  /// Override back to mock for offline/widget tests with:
  ///
  ///   flutter run --dart-define=USE_FIREBASE=false
  ///
  /// Requires lib/firebase_options.dart (flutterfire configure) and the
  /// deployed cloud/database.rules.json.
  static const bool useFirebase =
      bool.fromEnvironment('USE_FIREBASE', defaultValue: true);
}
