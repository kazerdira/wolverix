import 'package:get/get.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

class AuthProvider extends GetxController {
  final ApiService _api = Get.find<ApiService>();
  final StorageService _storage = Get.find<StorageService>();

  final Rx<User?> currentUser = Rx<User?>(null);
  final Rx<UserStats?> userStats = Rx<UserStats?>(null);
  final RxBool isLoading = false.obs;
  final RxBool isAuthenticated = false.obs;
  final RxString errorMessage = ''.obs;

  // Future that completes when auth check is done
  late final Future<void> isInitialized;

  User? get user => currentUser.value;

  @override
  void onInit() {
    super.onInit();
    isInitialized = _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    final authenticated = await _storage.isAuthenticated();
    if (authenticated) {
      await fetchCurrentUser();
    }
    isAuthenticated.value = authenticated && currentUser.value != null;
  }

  Future<bool> register(String username, String email, String password) async {
    try {
      isLoading.value = true;
      errorMessage.value = '';

      final response = await _api.register(username, email, password);

      await _storage.setAccessToken(response.accessToken);
      await _storage.setRefreshToken(response.refreshToken);
      _storage.setUserId(response.user.id);
      _storage.setUsername(response.user.username);

      currentUser.value = response.user;
      isAuthenticated.value = true;

      return true;
    } catch (e) {
      errorMessage.value = _extractErrorMessage(e);
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  Future<bool> login(String email, String password) async {
    try {
      isLoading.value = true;
      errorMessage.value = '';

      final response = await _api.login(email, password);

      await _storage.setAccessToken(response.accessToken);
      await _storage.setRefreshToken(response.refreshToken);
      _storage.setUserId(response.user.id);
      _storage.setUsername(response.user.username);

      currentUser.value = response.user;
      isAuthenticated.value = true;

      return true;
    } catch (e) {
      errorMessage.value = _extractErrorMessage(e);
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> logout() async {
    await _storage.clearAuth();
    currentUser.value = null;
    userStats.value = null;
    isAuthenticated.value = false;
    Get.offAllNamed('/login');
  }

  Future<void> fetchCurrentUser() async {
    try {
      final user = await _api.getCurrentUser();
      currentUser.value = user;
      _storage.setUserId(user.id);
      _storage.setUsername(user.username);
    } catch (e) {
      print('Failed to fetch current user: $e');
      // Token might be expired, try to refresh
      isAuthenticated.value = false;
    }
  }

  Future<void> fetchUserStats() async {
    try {
      final stats = await _api.getUserStats();
      userStats.value = stats;
    } catch (e) {
      print('Failed to fetch user stats: $e');
    }
  }

  Future<bool> updateProfile(Map<String, dynamic> data) async {
    try {
      isLoading.value = true;
      final user = await _api.updateUser(data);
      currentUser.value = user;
      return true;
    } catch (e) {
      errorMessage.value = _extractErrorMessage(e);
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  String _extractErrorMessage(dynamic error) {
    if (error.toString().contains('401')) {
      return 'Invalid credentials';
    } else if (error.toString().contains('409')) {
      return 'Email or username already exists';
    } else if (error.toString().contains('Network')) {
      return 'Network error. Please check your connection.';
    }
    return 'An error occurred. Please try again.';
  }
}
