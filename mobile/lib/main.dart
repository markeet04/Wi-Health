import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'app_config.dart';
import 'auth/auth_controller.dart';
import 'firebase_options.dart';
import 'models.dart';
import 'screens/alert_detail_screen.dart';
import 'screens/complaint_chat_screen.dart';
import 'screens/splash_screen.dart';
import 'theme.dart';

final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
bool _notificationPermissionRequested = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (AppConfig.useFirebase) {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
    await _initializeLocalNotifications();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  runApp(const WiHealthApp());
}

Future<bool> _ensureNotificationPermission() async {
  if (_notificationPermissionRequested) {
    return true;
  }

  final messaging = FirebaseMessaging.instance;
  final settings = await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
    provisional: true,
  );

  await messaging.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );

  final androidPlugin = _localNotifications
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  final androidGranted = await androidPlugin?.requestNotificationsPermission() ?? true;

  _notificationPermissionRequested = true;
  return settings.authorizationStatus != AuthorizationStatus.denied && androidGranted;
}

Future<void> _initializeLocalNotifications() async {
  const androidInitSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidInitSettings);
  await _localNotifications.initialize(initSettings);

  await _localNotifications
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(const AndroidNotificationChannel(
        'chat_notifications',
        'Chat notifications',
        description: 'Notifications for support and alert updates',
        importance: Importance.high,
      ));

  await _ensureNotificationPermission();
}

Future<void> _showLocalNotification(RemoteMessage message) async {
  if (!await _ensureNotificationPermission()) {
    return;
  }
  final title = message.notification?.title ?? 'Wi-Health';
  final body = message.notification?.body ?? 'You have a new update';
  final id = message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch;

  await _localNotifications.show(
    id,
    title,
    body,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'chat_notifications',
        'Chat notifications',
        channelDescription: 'Notifications for support and alert updates',
        importance: Importance.high,
        priority: Priority.high,
      ),
    ),
  );
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await _initializeLocalNotifications();
  await _showLocalNotification(message);
}

class WiHealthApp extends StatefulWidget {
  const WiHealthApp({super.key});

  @override
  State<WiHealthApp> createState() => _WiHealthAppState();
}

class _WiHealthAppState extends State<WiHealthApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    if (AppConfig.useFirebase) {
      FirebaseMessaging.instance.getInitialMessage().then((message) {
        if (!mounted) return;
        if (message != null) {
          _handleMessage(message);
        }
      });
      FirebaseMessaging.onMessage.listen((message) async {
        if (!mounted) return;
        await _showLocalNotification(message);
        _handleMessage(message);
      });
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        if (!mounted) return;
        _handleMessage(message);
      });
    }
  }

  void _handleMessage(RemoteMessage message) {
    final alertId = message.data['alertId']?.toString();
    final patientId = message.data['patientId']?.toString();
    final complaintId = message.data['complaintId']?.toString();
    if (authController.user == null) {
      return;
    }

    if (complaintId != null) {
      _navigatorKey.currentState?.push(MaterialPageRoute(
        builder: (_) => ComplaintChatScreen(
          app: AppStateRegistry.shared,
          complaintId: complaintId,
        ),
      ));
      return;
    }

    if (alertId == null || patientId == null) {
      return;
    }

    final alert = AnomalyAlert(
      id: alertId,
      patientId: patientId,
      title: message.notification?.title ?? 'Alert',
      severity: AlertSeverity.info,
      time: 'Now',
      day: 'Today',
      summary: message.notification?.body ?? 'Alert received',
      detail: const {},
    );

    _navigatorKey.currentState?.push(MaterialPageRoute(
      builder: (_) => AlertDetailScreen(app: AppStateRegistry.shared, alert: alert),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Wi-Health',
      debugShowCheckedModeBanner: false,
      theme: buildWiTheme(),
      home: const SplashScreen(),
    );
  }
}
