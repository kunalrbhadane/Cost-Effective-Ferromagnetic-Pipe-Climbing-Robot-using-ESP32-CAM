import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_joystick/flutter_joystick.dart';
import 'package:flutter_mjpeg/flutter_mjpeg.dart';

// --- Configuration ---
const String _robotIp = '192.168.4.1';
const String _webSocketUrl = 'ws://$_robotIp/ws';
const String _videoStreamUrl = 'http://$_robotIp:81/stream';
const double _proximityWarningDistance = 20.0;
const double _safeTiltAngle = 30.0;
enum JoystickDirection { up, down, left, right, center }

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESP32-CAM Robot Control',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blueGrey,
        scaffoldBackgroundColor: Colors.black,
        fontFamily: 'Orbitron', // Using the custom font!
      ),
      home: const ControlScreen(),
    );
  }
}

class ControlScreen extends StatefulWidget {
  const ControlScreen({super.key});
  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  WebSocketChannel? _channel;
  final StreamController<Map<String, dynamic>> _sensorDataController = StreamController.broadcast();
  bool _isConnected = false;
  String _lastCommand = "stop";
  static const double _joystickDeadzone = 0.7;
  JoystickDirection _joystickDirection = JoystickDirection.center;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void dispose() {
    _sensorDataController.close();
    _disconnect();
    super.dispose();
  }

  void _connect() {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(_webSocketUrl));
      if (mounted) setState(() => _isConnected = true);
      _channel!.stream.listen(
        (message) {
          if (mounted) {
            try { _sensorDataController.add(jsonDecode(message)); }
            catch (e) { debugPrint("Error decoding JSON: $e"); }
          }
        },
        onDone: () { if (mounted) setState(() => _isConnected = false); },
        onError: (error) { debugPrint("WS Error: $error"); if (mounted) setState(() => _isConnected = false); },
      );
    } catch (e) {
      debugPrint("Connection Error: $e");
      if (mounted) setState(() => _isConnected = false);
    }
  }

  void _disconnect() { _channel?.sink.close(); }
  void _reconnect() { if (!_isConnected) { _disconnect(); _connect(); } }

  void _sendCommandAndUpdateState(String command, JoystickDirection direction) {
    if (_isConnected && command != _lastCommand && _channel != null) {
      _channel!.sink.add(jsonEncode({'command': command}));
      _lastCommand = command;
    }
    setState(() {
      _joystickDirection = direction;
    });
  }

  void _handleJoystickMove(StickDragDetails details) {
    if (details.y < -_joystickDeadzone) {
      _sendCommandAndUpdateState("forward", JoystickDirection.up);
    } else if (details.y > _joystickDeadzone) {
      _sendCommandAndUpdateState("backward", JoystickDirection.down);
    } else if (details.x < -_joystickDeadzone) {
      _sendCommandAndUpdateState("left", JoystickDirection.left);
    } else if (details.x > _joystickDeadzone) {
      _sendCommandAndUpdateState("right", JoystickDirection.right);
    } else {
      _sendCommandAndUpdateState("stop", JoystickDirection.center);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: OrientationBuilder(
          builder: (context, orientation) {
            return Stack(
              children: [
                Mjpeg(
                  stream: _videoStreamUrl,
                  width: MediaQuery.of(context).size.width,
                  height: MediaQuery.of(context).size.height,
                  isLive: true,
                  loading: (context) => _buildMessageOverlay(icon: Icons.videocam, message: "Connecting..."),
                  error: (context, error, stack) => _buildMessageOverlay(icon: Icons.videocam_off, message: "Video Stream Failed"),
                ),
                if (orientation == Orientation.landscape)
                  _buildLandscapeLayout()
                else
                  _buildPortraitLayout(),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildLandscapeLayout() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [_buildConnectionStatus(), _buildSensorPanel()],
          ),
          _buildJoystickArea(),
        ],
      ),
    );
  }

  Widget _buildPortraitLayout() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [ _buildConnectionStatus(), Flexible(child: _buildSensorPanel(isPortrait: true)) ],
          ),
        ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.only(bottom: 40.0),
          child: _buildJoystickArea(),
        ),
      ],
    );
  }

  Widget _buildJoystickArea() {
    return SizedBox(
      width: 150,
      height: 150,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _buildJoystickBase(),
          Joystick(
            mode: JoystickMode.all,
            listener: _handleJoystickMove,
            onStickDragEnd: () => _sendCommandAndUpdateState("stop", JoystickDirection.center),
            base: Container(),
          ),
        ],
      ),
    );
  }

  Widget _buildJoystickBase() {
    return Container(
      width: 150,
      height: 150,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withOpacity(0.5),
        border: Border.all(color: Colors.blueGrey.shade800, width: 4),
      ),
      child: Stack(
        children: [
          _buildArrow(JoystickDirection.up, Icons.keyboard_arrow_up, Alignment.topCenter),
          _buildArrow(JoystickDirection.down, Icons.keyboard_arrow_down, Alignment.bottomCenter),
          _buildArrow(JoystickDirection.left, Icons.keyboard_arrow_left, Alignment.centerLeft),
          _buildArrow(JoystickDirection.right, Icons.keyboard_arrow_right, Alignment.centerRight),
        ],
      ),
    );
  }

  Widget _buildArrow(JoystickDirection direction, IconData icon, Alignment alignment) {
    final bool isSelected = _joystickDirection == direction;
    final Color color = isSelected ? Colors.greenAccent : Colors.white24;
    final double iconSize = isSelected ? 50.0 : 40.0;
    final List<BoxShadow>? boxShadow = isSelected ? [ BoxShadow( color: Colors.greenAccent.withOpacity(0.7), blurRadius: 15.0, spreadRadius: 5.0 )] : null;

    return Align(
      alignment: alignment,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeInOut,
        margin: const EdgeInsets.all(12.0),
        decoration: BoxDecoration( shape: BoxShape.circle, boxShadow: boxShadow),
        child: Icon(icon, color: color, size: iconSize),
      ),
    );
  }

  Widget _buildSensorPanel({bool isPortrait = false}) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: _sensorDataController.stream,
      builder: (context, snapshot) {
        double distance = -1.0, tilt = 0.0;
        bool edge = false;
        if (snapshot.hasData && snapshot.data != null) {
          final data = snapshot.data!;
          distance = double.tryParse(data['distance']?.toString() ?? '-1.0') ?? -1.0;
          tilt = double.tryParse(data['tilt']?.toString() ?? '0.0') ?? 0.0;
          edge = data['edge'] == true;
        }
        final isProximityAlert = distance >= 0 && distance < _proximityWarningDistance;
        final isTiltAlert = tilt.abs() > _safeTiltAngle;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.black.withOpacity(0.65), borderRadius: BorderRadius.circular(10)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSensorDisplay( icon: Icons.sensors, label: 'Distance', value: distance >= 0 ? '${distance.toStringAsFixed(1)} cm' : 'N/A', isAlert: isProximityAlert, alertColor: Colors.redAccent, progress: distance >= 0 ? (1.0 - (distance / (_proximityWarningDistance * 2))).clamp(0.0, 1.0) : null),
              SizedBox(height: isPortrait ? 8 : 12),
              _buildSensorDisplay( icon: Icons.screen_rotation, label: 'Tilt Angle', value: '${tilt.toStringAsFixed(1)}°', isAlert: isTiltAlert),
              SizedBox(height: isPortrait ? 8 : 12),
              _buildSensorDisplay( icon: Icons.warning_amber_rounded, label: 'Edge (IR)', value: edge ? 'DETECTED' : 'Clear', isAlert: edge),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSensorDisplay({ required IconData icon, required String label, required String value, required bool isAlert, double? progress, Color alertColor = Colors.orangeAccent }) {
    final displayColor = isAlert ? alertColor : Colors.white;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: displayColor, size: 20),
            const SizedBox(width: 8),
            Text('$label:', style: const TextStyle(fontSize: 16, color: Colors.white70)),
            const SizedBox(width: 8),
            Text(value, style: TextStyle( fontSize: 18, color: displayColor, fontWeight: isAlert ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
        if (progress != null) ...[
          const SizedBox(height: 4),
          SizedBox( width: 150, child: LinearProgressIndicator( value: progress, backgroundColor: Colors.grey.withOpacity(0.3), valueColor: AlwaysStoppedAnimation<Color>(displayColor), minHeight: 6)),
        ]
      ],
    );
  }

  Widget _buildConnectionStatus() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration( color: _isConnected ? Colors.green.withOpacity(0.8) : Colors.red.withOpacity(0.8), borderRadius: BorderRadius.circular(20)),
          child: Text( _isConnected ? "CONNECTED" : "DISCONNECTED", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        if (!_isConnected)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: ElevatedButton.icon( onPressed: _reconnect, icon: const Icon(Icons.refresh), label: const Text('Reconnect'), style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey.withOpacity(0.8))),
          )
      ],
    );
  }

  Widget _buildMessageOverlay({required IconData icon, required String message}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white70, size: 60),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: Colors.white, fontSize: 16)),
        ],
      ),
    );
  }
}  