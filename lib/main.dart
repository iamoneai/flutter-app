// IAMONEAI - Fresh Start
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'user/screens/auth_wrapper.dart';
import 'admin/screens/admin_auth_wrapper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const IamoneaiApp());
}

class IamoneaiApp extends StatelessWidget {
  const IamoneaiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IAMONEAI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A1A1A),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFFAFAFA),
      ),
      initialRoute: '/',
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/admin':
            return MaterialPageRoute(
              builder: (_) => const AdminAuthWrapper(),
            );
          case '/':
          default:
            return MaterialPageRoute(
              builder: (_) => const AuthWrapper(),
            );
        }
      },
    );
  }
}
