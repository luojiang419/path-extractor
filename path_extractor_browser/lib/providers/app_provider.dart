import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

class ToastMessage {
  final String text;
  final bool isError;
  final DateTime createdAt;

  ToastMessage({required this.text, this.isError = false, DateTime? createdAt})
    : createdAt = createdAt ?? DateTime.now();
}

class ToastState {
  final ToastMessage? message;
  final bool isVisible;

  const ToastState({this.message, this.isVisible = false});
}

class ToastNotifier extends StateNotifier<ToastState> {
  ToastNotifier() : super(const ToastState());

  void showSuccess(String text) {
    state = ToastState(
      message: ToastMessage(text: text, isError: false),
      isVisible: true,
    );
  }

  void showError(String text) {
    state = ToastState(
      message: ToastMessage(text: text, isError: true),
      isVisible: true,
    );
  }

  void dismiss() {
    state = ToastState(message: state.message, isVisible: false);
  }
}

final toastProvider = StateNotifierProvider<ToastNotifier, ToastState>(
  (ref) => ToastNotifier(),
);
