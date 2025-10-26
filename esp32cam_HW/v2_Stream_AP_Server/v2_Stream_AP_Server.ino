// v1_cameraWebServer.ino (Updated for Access Point Mode)

#include "esp_camera.h"
#include <WiFi.h>

// ===========================
// Select camera model (defined in board_config.h)
// ===========================
#include "board_config.h"

// ==============================================================
// --- MODIFIED FOR ACCESS POINT (AP) MODE ---
// ESP32-CAM will create its own WiFi network for the app to connect to.
// ==============================================================
const char *ssid = "PipeRobot-AP";
const char *password = "robot12345";

// Forward declaration of the function from app_httpd.cpp
void startCameraServer();
void setupLedFlash();

void setup() {
  Serial.begin(115200);
  Serial.setDebugOutput(true);
  Serial.println();

  camera_config_t config;
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer = LEDC_TIMER_0;
  config.pin_d0 = Y2_GPIO_NUM;
  config.pin_d1 = Y3_GPIO_NUM;
  config.pin_d2 = Y4_GPIO_NUM;
  config.pin_d3 = Y5_GPIO_NUM;
  config.pin_d4 = Y6_GPIO_NUM;
  config.pin_d5 = Y7_GPIO_NUM;
  config.pin_d6 = Y8_GPIO_NUM;
  config.pin_d7 = Y9_GPIO_NUM;
  config.pin_xclk = XCLK_GPIO_NUM;
  config.pin_pclk = PCLK_GPIO_NUM;
  config.pin_vsync = VSYNC_GPIO_NUM;
  config.pin_href = HREF_GPIO_NUM;
  config.pin_sccb_sda = SIOD_GPIO_NUM;
  config.pin_sccb_scl = SIOC_GPIO_NUM;
  config.pin_pwdn = PWDN_GPIO_NUM;
  config.pin_reset = RESET_GPIO_NUM;
  config.xclk_freq_hz = 20000000;
  config.frame_size = FRAMESIZE_UXGA;
  config.pixel_format = PIXFORMAT_JPEG; // for streaming
  config.grab_mode = CAMERA_GRAB_WHEN_EMPTY;
  config.fb_location = CAMERA_FB_IN_PSRAM;
  config.jpeg_quality = 12;
  config.fb_count = 1;

  if (config.pixel_format == PIXFORMAT_JPEG) {
    if (psramFound()) {
      config.jpeg_quality = 10;
      config.fb_count = 2;
      config.grab_mode = CAMERA_GRAB_LATEST;
    } else {
      config.frame_size = FRAMESIZE_SVGA;
      config.fb_location = CAMERA_FB_IN_DRAM;
    }
  }

  // Camera init
  esp_err_t err = esp_camera_init(&config);
  if (err != ESP_OK) {
    Serial.printf("Camera init failed with error 0x%x", err);
    return;
  }

  sensor_t *s = esp_camera_sensor_get();
  // Drop down frame size for higher initial frame rate for streaming
  s->set_framesize(s, FRAMESIZE_QVGA);

#if defined(LED_GPIO_NUM)
  setupLedFlash();
#endif

  // --- Start the WiFi Access Point ---
  Serial.println("Starting WiFi Access Point...");
  WiFi.softAP(ssid, password);
  WiFi.setSleep(false); // Disable sleep mode for stable streaming
  
  Serial.println("\nESP32-CAM Access Point Started.");
  Serial.print("SSID: ");
  Serial.println(ssid);
  Serial.print("Password: ");
  Serial.println(password);
  Serial.print("AP IP address: ");
  Serial.println(WiFi.softAPIP()); // The app will connect to this IP

  // Start the web server from app_httpd.cpp
  startCameraServer();

  Serial.println("Camera Stream Server Ready!");
  Serial.print("Use 'http://");
  Serial.print(WiFi.softAPIP());
  Serial.println(":81/stream' to view the stream.");
}

void loop() {
  // Do nothing. Everything is handled by the web server task.
  delay(10000);
}