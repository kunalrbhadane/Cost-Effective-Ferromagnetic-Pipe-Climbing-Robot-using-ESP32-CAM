# ESP32-CAM Pipe Climbing Robot Control App

This repository contains the source code for a professional, HUD-style Flutter application designed to control an ESP32-CAM based pipe-climbing robot.

## 🚀 Features

*   **Live Video Stream:** Real-time MJPEG video feed from the robot's camera.
*   **Professional HUD Interface:** A gaming-style Heads-Up Display with custom fonts and graphics.
*   **Responsive Controls:** Joystick for intuitive movement with haptic feedback.
*   **Dynamic Sensor Dashboard:**
    *   Radial Proximity Gauge for obstacle distance.
    *   Alerts for unsafe tilt angles.
    *   Edge detection status from an IR sensor.
*   **Pulsing Alerts:** Key warnings have a subtle pulsing animation to draw attention.
*   **Robust Connectivity:** Clear connection status and a one-tap reconnect button.

## ⚙️ Hardware & Firmware

This application is the client-side controller. It is designed to work with an ESP32-CAM running a specific C++ firmware that provides:

*   A Wi-Fi Access Point.
*   An MJPEG video stream on port 81.
*   A WebSocket server on port 80 for commands and sensor data.

## 🛠️ Setup & Run

1.  **Clone the repository:**
    ```bash
    git clone [Your-Repo-URL]
    cd esp32campapp
    ```

2.  **Get Flutter packages:**
    ```bash
    flutter pub get
    ```

3.  **Run the app:**
    Connect a device and run the following command:
    ```bash
    flutter run
    ```
