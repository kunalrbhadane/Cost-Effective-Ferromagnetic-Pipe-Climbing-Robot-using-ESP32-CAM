import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_joystick/flutter_joystick.dart';
import 'package:flutter_mjpeg/flutter_mjpeg.dart';

// ====================================================================
// --- 1. Configuration ---
// ====================================================================
// The default IP address of the ESP32-CAM when in Access Point mode.
const String _robotIp = '192.168.4.1';
const String _webSocketUrl = 'ws://$_robotIp/ws';
const String _videoStreamUrl = 'http://$_robotIp:81/stream';

// --- Alert Thresholds ---
// Customize these values to change the sensitivity of the dashboard alerts.
const double _proximityWarningDistance = 20.0; // Distance in cm to trigger the red alert.
const double _safeTiltAngle = 30.0; // Max tilt angle in degrees before the orange alert.

// ====================================================================
// --- 2. Application Entry Point ---
// ====================================================================
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Enable immersive fullscreen mode.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  // NOTE: We do NOT lock orientation, allowing the app to be responsive.
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
      ),
      home: const ControlScreen(),
    );
  }
}

// ====================================================================
// --- 3. Main Control Screen ---
// ====================================================================
class ControlScreen extends StatefulWidget {
  const ControlScreen({super.key});

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  // --- State Variables ---
  WebSocketChannel? _channel;
  final StreamController<Map<String, dynamic>> _sensorDataController = StreamController.broadcast();
  bool _isConnected = false;
  String _lastCommand = "stop";

  static const double _joystickDeadzone = 0.7;

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

  // --- Core Logic: Connection and Communication ---
  void _connect() {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(_webSocketUrl));
      if (mounted) setState(() => _isConnected = true);

      _channel!.stream.listen(
        (message) {
          if (mounted) {
            try {
              _sensorDataController.add(jsonDecode(message));
            } catch (e) {
              debugPrint("Error decoding JSON: $e");
            }
          }
        },
        onDone: () { if (mounted) setState(() => _isConnected = false); },
        onError: (error) {
          debugPrint("WebSocket Error: $error");
          if (mounted) setState(() => _isConnected = false);
        },
      );
    } catch (e) {
      debugPrint("Error connecting to WebSocket: $e");
      if (mounted) setState(() => _isConnected = false);
    }
  }

  void _disconnect() {
    _channel?.sink.close();
  }

  void _reconnect() {
    if (!_isConnected) {
      _disconnect();
      _connect();
    }
  }

  void _sendCommand(String command) {
    if (_isConnected && command != _lastCommand && _channel != null) {
      _channel!.sink.add(jsonEncode({'command': command}));
      _lastCommand = command;
    }
  }

  void _handleJoystickMove(StickDragDetails details) {
    if (details.y < -_joystickDeadzone) _sendCommand("forward");
    else if (details.y > _joystickDeadzone) _sendCommand("backward");
    else if (details.x < -_joystickDeadzone) _sendCommand("left");
    else if (details.x > _joystickDeadzone) _sendCommand("right");
    else _sendCommand("stop");
  }

  // --- Main Build Method with Adaptive Layout ---
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

  // ====================================================================
  // --- 4. Layout and Widget Builders ---
  // ====================================================================

  /// Builds the UI for horizontal (landscape) orientation.
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
          Joystick(
            mode: JoystickMode.all,
            listener: _handleJoystickMove,
            onStickDragEnd: () => _sendCommand("stop"),
          ),
        ],
      ),
    );
  }

  /// Builds the UI for vertical (portrait) orientation.
  Widget _buildPortraitLayout() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildConnectionStatus(),
              Flexible(child: _buildSensorPanel(isPortrait: true)),
            ],
          ),
        ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.only(bottom: 40.0),
          child: Joystick(
            mode: JoystickMode.all,
            listener: _handleJoystickMove,
            onStickDragEnd: () => _sendCommand("stop"),
          ),
        ),
      ],
    );
  }

  /// Builds the enhanced sensor dashboard panel.
  Widget _buildSensorPanel({bool isPortrait = false}) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: _sensorDataController.stream,
      builder: (context, snapshot) {
        // Use default/error values if no data is present yet
        double distance = -1.0;
        double tilt = 0.0;
        bool edge = false;

        if (snapshot.hasData && snapshot.data != null) {
          final data = snapshot.data!;
          distance = double.tryParse(data['distance']?.toString() ?? '-1.0') ?? -1.0;
          tilt = double.tryParse(data['tilt']?.toString() ?? '0.0') ?? 0.0;
          edge = data['edge'] == true;
        }

        // Determine alert states based on thresholds
        final bool isProximityAlert = distance >= 0 && distance < _proximityWarningDistance;
        final bool isTiltAlert = tilt.abs() > _safeTiltAngle;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.black.withOpacity(0.65), borderRadius: BorderRadius.circular(10)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSensorDisplay(
                icon: Icons.sensors,
                label: 'Distance',
                value: distance >= 0 ? '${distance.toStringAsFixed(1)} cm' : 'N/A',
                isAlert: isProximityAlert,
                alertColor: Colors.redAccent,
                progress: distance >= 0 ? (1.0 - (distance / (_proximityWarningDistance * 2))).clamp(0.0, 1.0) : null,
              ),
              SizedBox(height: isPortrait ? 8 : 12),
              _buildSensorDisplay(
                icon: Icons.screen_rotation,
                label: 'Tilt Angle',
                value: '${tilt.toStringAsFixed(1)}°',
                isAlert: isTiltAlert,
              ),
              SizedBox(height: isPortrait ? 8 : 12),
              _buildSensorDisplay(
                icon: Icons.warning_amber_rounded,
                label: 'Edge (IR)',
                value: edge ? 'DETECTED' : 'Clear',
                isAlert: edge,
              ),
            ],
          ),
        );
      },
    );
  }

  /// Builds a single row in the sensor dashboard, handling alert visuals.
  Widget _buildSensorDisplay({
    required IconData icon,
    required String label,
    required String value,
    required bool isAlert,
    double? progress,
    Color alertColor = Colors.orangeAccent,
  }) {
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
            Text(value, style: TextStyle(
                fontSize: 18,
                color: displayColor,
                fontWeight: isAlert ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
        if (progress != null) ...[
          const SizedBox(height: 4),
          SizedBox(
            width: 150,
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.grey.withOpacity(0.3),
              valueColor: AlwaysStoppedAnimation<Color>(displayColor),
              minHeight: 6,
            ),
          )
        ]
      ],
    );
  }

  /// Builds the connection status indicator ("CONNECTED" / "DISCONNECTED").
  Widget _buildConnectionStatus() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _isConnected ? Colors.green.withOpacity(0.8) : Colors.red.withOpacity(0.8),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            _isConnected ? "CONNECTED" : "DISCONNECTED",
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        if (!_isConnected)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: ElevatedButton.icon(
              onPressed: _reconnect,
              icon: const Icon(Icons.refresh),
              label: const Text('Reconnect'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey.withOpacity(0.8)),
            ),
          )
      ],
    );
  }

  /// A generic widget to show an icon and message for loading/error states.
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