import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:werewolf_voice/services/agora_service.dart';
import 'package:werewolf_voice/services/api_service.dart';
import 'package:werewolf_voice/services/websocket_service.dart';

void main() {
  // Initialize services
  Get.put(ApiService());
  Get.put(AgoraService());
  Get.put(WebSocketService());

  runApp(const WerewolfVoiceApp());
}

class WerewolfVoiceApp extends StatelessWidget {
  const WerewolfVoiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Werewolf Voice',
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1A1A2E),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF16213E),
          elevation: 0,
        ),
        cardTheme: CardTheme(
          color: const Color(0xFF0F3460),
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFE94560),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF16213E),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE94560), width: 2),
          ),
        ),
      ),
      home: const SplashScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    // Add initialization logic here
    // - Check if user is logged in
    // - Initialize Agora
    // - Navigate to appropriate screen
    
    await Future.delayed(const Duration(seconds: 2));
    
    // For now, navigate to login screen
    Get.off(() => const LoginScreen());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.groups,
              size: 100,
              color: Theme.of(context).primaryColor,
            ),
            const SizedBox(height: 24),
            const Text(
              'Werewolf Voice',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Voice Room Social Gaming',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 48),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

// Placeholder screens - implement these based on your design
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Login'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.group,
              size: 80,
              color: Color(0xFFE94560),
            ),
            const SizedBox(height: 48),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Username',
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                prefixIcon: Icon(Icons.lock),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  // Implement login logic
                  Get.to(() => const HomeScreen());
                },
                child: const Text('Login'),
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                // Navigate to register screen
              },
              child: const Text('Don\'t have an account? Register'),
            ),
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Werewolf Voice'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () {
              // Navigate to profile
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Room list would go here
          Expanded(
            child: Center(
              child: Text(
                'Room List Coming Soon',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.grey[400],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          // Create room
        },
        icon: const Icon(Icons.add),
        label: const Text('Create Room'),
      ),
    );
  }
}
