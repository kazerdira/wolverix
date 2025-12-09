import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Centralized error handling for Wolverix
class ErrorHandler {
  static final ErrorHandler _instance = ErrorHandler._internal();
  factory ErrorHandler() => _instance;
  ErrorHandler._internal();

  final RxBool isOffline = false.obs;
  StreamSubscription? _connectivitySubscription;

  void init() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((result) {
      isOffline.value = result == ConnectivityResult.none;
      if (isOffline.value) {
        _showOfflineBanner();
      }
    });
  }

  void dispose() {
    _connectivitySubscription?.cancel();
  }

  /// Parse and handle API errors with user-friendly messages
  AppError parseError(dynamic error) {
    if (error is DioException) {
      return _parseDioError(error);
    } else if (error is SocketException) {
      return AppError(
        type: ErrorType.network,
        message: 'No internet connection',
        userMessage: 'Please check your internet connection and try again.',
        isRetryable: true,
      );
    } else if (error is TimeoutException) {
      return AppError(
        type: ErrorType.timeout,
        message: 'Request timed out',
        userMessage: 'The server is taking too long to respond. Please try again.',
        isRetryable: true,
      );
    }
    
    return AppError(
      type: ErrorType.unknown,
      message: error.toString(),
      userMessage: 'Something went wrong. Please try again.',
      isRetryable: true,
    );
  }

  AppError _parseDioError(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return AppError(
          type: ErrorType.timeout,
          message: 'Connection timed out',
          userMessage: 'Connection is slow. Please try again.',
          isRetryable: true,
        );
      
      case DioExceptionType.connectionError:
        return AppError(
          type: ErrorType.network,
          message: 'Connection error',
          userMessage: 'Unable to connect to server. Please check your connection.',
          isRetryable: true,
        );
      
      case DioExceptionType.badResponse:
        return _parseHttpError(error.response?.statusCode, error.response?.data);
      
      default:
        return AppError(
          type: ErrorType.unknown,
          message: error.message ?? 'Unknown error',
          userMessage: 'Something went wrong. Please try again.',
          isRetryable: true,
        );
    }
  }

  AppError _parseHttpError(int? statusCode, dynamic data) {
    final serverMessage = data is Map ? data['error'] as String? : null;
    
    switch (statusCode) {
      case 400:
        return AppError(
          type: ErrorType.validation,
          message: serverMessage ?? 'Bad request',
          userMessage: _getValidationMessage(serverMessage),
          isRetryable: false,
        );
      
      case 401:
        return AppError(
          type: ErrorType.authentication,
          message: 'Unauthorized',
          userMessage: 'Your session has expired. Please login again.',
          isRetryable: false,
          action: ErrorAction.logout,
        );
      
      case 403:
        return AppError(
          type: ErrorType.authorization,
          message: serverMessage ?? 'Forbidden',
          userMessage: _getAuthorizationMessage(serverMessage),
          isRetryable: false,
        );
      
      case 404:
        return AppError(
          type: ErrorType.notFound,
          message: serverMessage ?? 'Not found',
          userMessage: _getNotFoundMessage(serverMessage),
          isRetryable: false,
        );
      
      case 409:
        return AppError(
          type: ErrorType.conflict,
          message: serverMessage ?? 'Conflict',
          userMessage: serverMessage ?? 'This action conflicts with existing data.',
          isRetryable: false,
        );
      
      case 500:
      case 502:
      case 503:
        return AppError(
          type: ErrorType.server,
          message: 'Server error',
          userMessage: 'Server is having issues. Please try again later.',
          isRetryable: true,
        );
      
      default:
        return AppError(
          type: ErrorType.unknown,
          message: 'HTTP $statusCode',
          userMessage: 'Something went wrong. Please try again.',
          isRetryable: true,
        );
    }
  }

  String _getValidationMessage(String? serverMessage) {
    if (serverMessage == null) return 'Invalid input. Please check and try again.';
    
    if (serverMessage.contains('already in an active room')) {
      return 'You\'re already in a room. Leave it first to join another.';
    }
    if (serverMessage.contains('room is full')) {
      return 'This room is full. Try another one!';
    }
    if (serverMessage.contains('not enough players')) {
      return 'Need at least 5 players to start the game.';
    }
    if (serverMessage.contains('all players must be ready')) {
      return 'Waiting for all players to be ready.';
    }
    if (serverMessage.contains('username') && serverMessage.contains('exists')) {
      return 'This username is taken. Try another one!';
    }
    if (serverMessage.contains('email') && serverMessage.contains('exists')) {
      return 'An account with this email already exists.';
    }
    
    return serverMessage;
  }

  String _getAuthorizationMessage(String? serverMessage) {
    if (serverMessage?.contains('host') ?? false) {
      return 'Only the room host can do this.';
    }
    return 'You don\'t have permission for this action.';
  }

  String _getNotFoundMessage(String? serverMessage) {
    if (serverMessage?.contains('room') ?? false) {
      return 'Room not found. It may have been closed.';
    }
    if (serverMessage?.contains('player') ?? false) {
      return 'Player not found.';
    }
    return 'The requested resource was not found.';
  }

  void _showOfflineBanner() {
    Get.rawSnackbar(
      message: 'You\'re offline',
      icon: const Icon(Icons.wifi_off, color: Colors.white),
      backgroundColor: Colors.grey.shade800,
      duration: const Duration(seconds: 3),
      snackPosition: SnackPosition.TOP,
      margin: const EdgeInsets.all(16),
      borderRadius: 12,
    );
  }

  /// Show error with optional retry action
  void showError(AppError error, {VoidCallback? onRetry}) {
    Get.snackbar(
      _getErrorTitle(error.type),
      error.userMessage,
      icon: Icon(_getErrorIcon(error.type), color: Colors.white),
      backgroundColor: _getErrorColor(error.type),
      colorText: Colors.white,
      duration: const Duration(seconds: 4),
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.all(16),
      borderRadius: 12,
      mainButton: error.isRetryable && onRetry != null
          ? TextButton(
              onPressed: () {
                Get.back();
                onRetry();
              },
              child: const Text('RETRY', style: TextStyle(color: Colors.white)),
            )
          : null,
    );

    // Handle special actions
    if (error.action == ErrorAction.logout) {
      Future.delayed(const Duration(seconds: 2), () {
        Get.offAllNamed('/login');
      });
    }
  }

  String _getErrorTitle(ErrorType type) {
    switch (type) {
      case ErrorType.network:
        return 'Connection Error';
      case ErrorType.timeout:
        return 'Timeout';
      case ErrorType.authentication:
        return 'Session Expired';
      case ErrorType.authorization:
        return 'Not Allowed';
      case ErrorType.validation:
        return 'Invalid Request';
      case ErrorType.notFound:
        return 'Not Found';
      case ErrorType.conflict:
        return 'Conflict';
      case ErrorType.server:
        return 'Server Error';
      default:
        return 'Error';
    }
  }

  IconData _getErrorIcon(ErrorType type) {
    switch (type) {
      case ErrorType.network:
        return Icons.wifi_off;
      case ErrorType.timeout:
        return Icons.timer_off;
      case ErrorType.authentication:
        return Icons.lock_outline;
      case ErrorType.authorization:
        return Icons.block;
      case ErrorType.validation:
        return Icons.warning_amber;
      case ErrorType.notFound:
        return Icons.search_off;
      case ErrorType.server:
        return Icons.cloud_off;
      default:
        return Icons.error_outline;
    }
  }

  Color _getErrorColor(ErrorType type) {
    switch (type) {
      case ErrorType.network:
      case ErrorType.timeout:
        return Colors.orange.shade700;
      case ErrorType.authentication:
      case ErrorType.authorization:
        return Colors.red.shade700;
      case ErrorType.server:
        return Colors.purple.shade700;
      default:
        return Colors.red.shade600;
    }
  }
}

enum ErrorType {
  network,
  timeout,
  authentication,
  authorization,
  validation,
  notFound,
  conflict,
  server,
  unknown,
}

enum ErrorAction {
  none,
  logout,
  refresh,
}

class AppError {
  final ErrorType type;
  final String message;
  final String userMessage;
  final bool isRetryable;
  final ErrorAction action;

  AppError({
    required this.type,
    required this.message,
    required this.userMessage,
    this.isRetryable = false,
    this.action = ErrorAction.none,
  });
}

/// Extension for easy error handling in providers
extension ErrorHandlerExtension on dynamic {
  void handleError(VoidCallback? onRetry) {
    final error = ErrorHandler().parseError(this);
    ErrorHandler().showError(error, onRetry: onRetry);
  }
}
