import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/data/auth_service.dart';
import 'features/auth/presentation/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables (.env)
  await dotenv.load(fileName: ".env");

  // Initialize Supabase client (for storage & direct sync)
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL'] ?? '',
    anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
  );

  // Initialize cached user session
  await AuthService().initialize();

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
          return const HomeScreenPlaceholder();
        }
        return const LoginScreen();
      },
    );
  }
}

class HomeScreenPlaceholder extends StatelessWidget {
  const HomeScreenPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final user = AuthService().currentUser;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              const Text(
                'CONNECTED',
                style: TextStyle(
                  color: AppColors.supportingText,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Welcome, ${user?.displayName ?? user?.email ?? 'User'}',
                style: const TextStyle(
                  color: AppColors.textHighContrast,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (user?.pairCode.isNotEmpty == true) ...[
                const SizedBox(height: 16),
                Text(
                  'Your Pair Code: ${user?.pairCode}',
                  style: const TextStyle(
                    color: AppColors.primaryAccent,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () async {
                    await AuthService().signOut();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.secondarySurface,
                    foregroundColor: AppColors.textHighContrast,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: AppColors.glassBorder),
                    ),
                  ),
                  child: const Text('Sign Out'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ConnectionCheckScreen extends StatefulWidget {
  const ConnectionCheckScreen({super.key});

  @override
  State<ConnectionCheckScreen> createState() => _ConnectionCheckScreenState();
}

class _ConnectionCheckScreenState extends State<ConnectionCheckScreen> {
  bool _isLoading = true;
  bool _isConnected = false;
  String _statusMessage = 'Connecting to Supabase...';

  @override
  void initState() {
    super.initState();
    _testConnection();
  }

  Future<void> _testConnection() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Checking Supabase connection...';
    });

    try {
      final client = Supabase.instance.client;
      // Test query to User table (which was created via Prisma)
      await client.from('User').select().limit(1);

      setState(() {
        _isConnected = true;
        _isLoading = false;
        _statusMessage = 'Connected to Supabase successfully! 🌲';
      });
    } catch (e) {
      setState(() {
        _isConnected = false;
        _isLoading = false;
        _statusMessage = 'Connection failed: ${e.toString()}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isConnected
                        ? Icons.check_circle_rounded
                        : (_isLoading ? Icons.hourglass_top_rounded : Icons.error_outline_rounded),
                    size: 64,
                    color: _isConnected
                        ? const Color(0xFF8E9A8E)
                        : (_isLoading ? AppColors.primaryAccent : Colors.redAccent),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'update_me',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _statusMessage,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  if (!_isLoading)
                    ElevatedButton.icon(
                      onPressed: _testConnection,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Test Connection Again'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
