import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../providers/room_provider.dart';
import '../../utils/theme.dart';

class JoinRoomScreen extends StatefulWidget {
  const JoinRoomScreen({super.key});

  @override
  State<JoinRoomScreen> createState() => _JoinRoomScreenState();
}

class _JoinRoomScreenState extends State<JoinRoomScreen> {
  final _codeController = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _joinRoom() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.length < 6) {
      Get.snackbar(
        'Invalid Code',
        'Please enter a valid 6-character room code',
        backgroundColor: WolverixTheme.errorColor,
        colorText: Colors.white,
      );
      return;
    }

    final roomProvider = Get.find<RoomProvider>();
    final success = await roomProvider.joinRoom(code);

    if (success && roomProvider.currentRoom.value != null) {
      Get.offNamed('/room/${roomProvider.currentRoom.value!.id}');
    } else {
      Get.snackbar(
        'Error',
        roomProvider.errorMessage.value,
        backgroundColor: WolverixTheme.errorColor,
        colorText: Colors.white,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Join Room')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: WolverixTheme.primaryColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.login,
                size: 50,
                color: WolverixTheme.primaryColor,
              ),
            ),
            const SizedBox(height: 30),
            // Title
            const Text(
              'Enter Room Code',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'Ask the host for the 6-character code',
              style: TextStyle(color: WolverixTheme.textSecondary),
            ),
            const SizedBox(height: 40),
            // Code input
            TextField(
              controller: _codeController,
              focusNode: _focusNode,
              textAlign: TextAlign.center,
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                letterSpacing: 10,
              ),
              decoration: InputDecoration(
                hintText: '------',
                hintStyle: TextStyle(
                  color: WolverixTheme.textHint.withOpacity(0.3),
                  letterSpacing: 10,
                ),
                counterText: '',
                filled: true,
                fillColor: WolverixTheme.cardColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
              ],
              onSubmitted: (_) => _joinRoom(),
            ),
            const SizedBox(height: 30),
            // Join button
            SizedBox(
              width: double.infinity,
              child: Obx(() {
                final roomProvider = Get.find<RoomProvider>();
                return ElevatedButton(
                  onPressed: roomProvider.isLoading.value ? null : _joinRoom,
                  child: roomProvider.isLoading.value
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Join Room'),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}
