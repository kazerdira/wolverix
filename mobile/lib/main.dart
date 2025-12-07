import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import 'providers/auth_provider.dart';
import 'providers/game_provider.dart';
import 'providers/room_provider.dart';
import 'providers/voice_provider.dart';
import 'services/api_service.dart';
import 'services/websocket_service.dart';
import 'services/agora_service.dart';
import 'services/storage_service.dart';
import 'screens/splash_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/room/room_lobby_screen.dart';
import 'screens/room/create_room_screen.dart';
import 'screens/room/join_room_screen.dart';
import 'screens/game/game_screen.dart';
import 'utils/theme.dart';
import 'utils/translations.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize storage
  await GetStorage.init();

  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set system UI style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF1a1a2e),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const WolverixApp());
}

class WolverixApp extends StatelessWidget {
  const WolverixApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Wolverix',
      debugShowCheckedModeBanner: false,
      theme: WolverixTheme.darkTheme,
      darkTheme: WolverixTheme.darkTheme,
      themeMode: ThemeMode.dark,
      translations: WolverixTranslations(),
      locale: Get.deviceLocale,
      fallbackLocale: const Locale('en', 'US'),
      initialBinding: AppBindings(),
      initialRoute: '/splash',
      getPages: [
        GetPage(name: '/splash', page: () => const SplashScreen()),
        GetPage(name: '/login', page: () => const LoginScreen()),
        GetPage(name: '/register', page: () => const RegisterScreen()),
        GetPage(name: '/home', page: () => const HomeScreen()),
        GetPage(name: '/create-room', page: () => const CreateRoomScreen()),
        GetPage(name: '/join-room', page: () => const JoinRoomScreen()),
        GetPage(name: '/room/:roomId', page: () => const RoomLobbyScreen()),
        GetPage(name: '/game/:sessionId', page: () => const GameScreen()),
      ],
    );
  }
}

class AppBindings extends Bindings {
  @override
  void dependencies() {
    // Services
    Get.lazyPut<StorageService>(() => StorageService(), fenix: true);
    Get.lazyPut<ApiService>(() => ApiService(), fenix: true);
    Get.lazyPut<WebSocketService>(() => WebSocketService(), fenix: true);
    Get.lazyPut<AgoraService>(() => AgoraService(), fenix: true);

    // Providers
    Get.lazyPut<AuthProvider>(() => AuthProvider(), fenix: true);
    Get.lazyPut<RoomProvider>(() => RoomProvider(), fenix: true);
    Get.lazyPut<GameProvider>(() => GameProvider(), fenix: true);
    Get.lazyPut<VoiceProvider>(() => VoiceProvider(), fenix: true);
  }
}
