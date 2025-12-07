import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../providers/room_provider.dart';
import '../../models/models.dart';
import '../../utils/theme.dart';

class CreateRoomScreen extends StatefulWidget {
  const CreateRoomScreen({super.key});

  @override
  State<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends State<CreateRoomScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  int _maxPlayers = 10;
  bool _isPrivate = false;

  // Game settings
  int _dayPhaseSeconds = 120;
  int _nightPhaseSeconds = 60;
  int _votingSeconds = 60;
  bool _enableVoiceChat = true;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _createRoom() async {
    if (!_formKey.currentState!.validate()) return;

    final roomProvider = Get.find<RoomProvider>();
    final room = await roomProvider.createRoom(
      name: _nameController.text.trim(),
      isPrivate: _isPrivate,
      maxPlayers: _maxPlayers,
      config: RoomConfig(
        dayPhaseSeconds: _dayPhaseSeconds,
        nightPhaseSeconds: _nightPhaseSeconds,
        votingSeconds: _votingSeconds,
        enableVoiceChat: _enableVoiceChat,
      ),
    );

    if (room != null) {
      Get.offNamed('/room/${room.id}');
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
      appBar: AppBar(title: const Text('Create Room')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Room name
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  hintText: 'Room Name',
                  prefixIcon: Icon(Icons.meeting_room_outlined),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a room name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // Max players slider
              Text(
                'Max Players: $_maxPlayers',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Slider(
                value: _maxPlayers.toDouble(),
                min: 6,
                max: 24,
                divisions: 18,
                label: '$_maxPlayers',
                onChanged: (value) {
                  setState(() {
                    _maxPlayers = value.toInt();
                  });
                },
              ),
              const SizedBox(height: 16),

              // Private room toggle
              SwitchListTile(
                title: const Text('Private Room'),
                subtitle: const Text('Only players with the code can join'),
                value: _isPrivate,
                onChanged: (value) {
                  setState(() {
                    _isPrivate = value;
                  });
                },
                contentPadding: EdgeInsets.zero,
              ),

              const Divider(height: 32),

              // Game settings
              const Text(
                'Game Settings',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              // Day phase duration
              _DurationSetting(
                label: 'Day Discussion',
                value: _dayPhaseSeconds,
                min: 60,
                max: 300,
                onChanged: (value) {
                  setState(() {
                    _dayPhaseSeconds = value;
                  });
                },
              ),

              // Night phase duration
              _DurationSetting(
                label: 'Night Phase',
                value: _nightPhaseSeconds,
                min: 30,
                max: 120,
                onChanged: (value) {
                  setState(() {
                    _nightPhaseSeconds = value;
                  });
                },
              ),

              // Voting duration
              _DurationSetting(
                label: 'Voting Time',
                value: _votingSeconds,
                min: 30,
                max: 120,
                onChanged: (value) {
                  setState(() {
                    _votingSeconds = value;
                  });
                },
              ),

              // Voice chat toggle
              SwitchListTile(
                title: const Text('Voice Chat'),
                subtitle: const Text('Enable real-time voice communication'),
                value: _enableVoiceChat,
                onChanged: (value) {
                  setState(() {
                    _enableVoiceChat = value;
                  });
                },
                contentPadding: EdgeInsets.zero,
              ),

              const SizedBox(height: 32),

              // Create button
              Obx(() {
                final roomProvider = Get.find<RoomProvider>();
                return ElevatedButton(
                  onPressed: roomProvider.isLoading.value ? null : _createRoom,
                  child: roomProvider.isLoading.value
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Create Room'),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

class _DurationSetting extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _DurationSetting({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text(
              '${value}s',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: WolverixTheme.primaryColor,
              ),
            ),
          ],
        ),
        Slider(
          value: value.toDouble(),
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: ((max - min) ~/ 10),
          onChanged: (v) => onChanged(v.toInt()),
        ),
      ],
    );
  }
}
