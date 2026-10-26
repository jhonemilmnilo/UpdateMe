import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/data/auth_service.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/couple/presentation/home_screen.dart';
import 'features/notifications/push_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables (.env)
  await dotenv.load(fileName: ".env");

  // Initialize Supabase client (for storage & direct sync)
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL'] ?? '',
    anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
  );

  // Initialize Firebase & FCM Background Handler
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Initialize cached user session
  await AuthService().initialize();

  // Initialize Push Notification Service (registers token with backend)
  await PushNotificationService().initialize();

  runApp(const UpdateMeApp());
}

class UpdateMeApp extends StatelessWidget {
  const UpdateMeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UpdateMe',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.stormCloudTheme,
      home: const AuthGateway(),
    );
  }
}

class AuthGateway extends StatelessWidget {
  const AuthGateway({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UserModel?>(
      valueListenable: AuthService().currentUserNotifier,
      builder: (context, user, _) {
        if (user != null) {
          return const HomeScreen();
        }
        return const LoginScreen();
      },
    );
  }
}
