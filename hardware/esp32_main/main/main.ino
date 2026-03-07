#include <WiFi.h>
#include <HTTPClient.h>
#include <TinyGPS++.h>
#include <HardwareSerial.h>
#include <Wire.h>

// ================= WIFI =================
const char* ssid = "iqoo1234";
const char* password = "hello123";

String firebaseURL = "https://esp32iotproject-e9fe1-default-rtdb.asia-southeast1.firebasedatabase.app";

// ================= TELEGRAM =================
String botToken = "8687058189:AAHyYqhE2UAjRLCQLPikGnOt88Uun6rJVVg"; 

String chatIDs[] = {
  "1206334941",      // Your ID
  "7681145312",  // Contact 2
  "7710246439",  //Anwesha Das
  "7015801586",  //Anisha Majumdar
};

const int totalContacts = 4;

// ================= GPS =================
TinyGPSPlus gps;
HardwareSerial gpsSerial(2);

// ================= MPU6500 =================
#define MPU_ADDR 0x68

float ax, ay, az;
float gx, gy, gz;

bool autoTriggered = false;

bool freeFallDetected = false;
unsigned long freeFallTime = 0;
bool impactDetected = false;
unsigned long impactTime = 0;

// ================= TRACKING =================
bool trackingActive = false;
float lat = 0.0;
float lng = 0.0;

// ================= BUTTON =================
#define SOS_BUTTON 14

bool lastButtonState = HIGH;
unsigned long pressStartTime = 0;
int clickCount = 0;
unsigned long lastClickTime = 0;

const unsigned long MULTI_CLICK_DELAY = 600;
const unsigned long STOP_HOLD_TIME = 5000;

// ================= TIMERS =================
unsigned long lastSendTime = 0;
const unsigned long SEND_INTERVAL = 5000;

unsigned long lastTelegramSend = 0;
const unsigned long TELEGRAM_INTERVAL = 30000;  // 30 sec

// ================= FUNCTION DECLARATIONS =================
void sendActiveData();
void sendActiveWithoutGPS();
void sendIdleStatus();
void sendTelegramAlert(String message);
void sendSOSFlag();
void readMPU();

void setup() {

  Serial.begin(115200);
  gpsSerial.begin(9600, SERIAL_8N1, 16, 17);

  pinMode(SOS_BUTTON, INPUT_PULLUP);

  WiFi.begin(ssid, password);
  Serial.print("Connecting to WiFi");

  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }

  Serial.println("\nConnected to WiFi");

  // Initialize MPU6500
  Wire.begin(21, 22);
  Wire.setClock(100000);

  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x6B);
  Wire.write(0x00);
  Wire.endTransmission();

  // Set accelerometer to ±2g
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x1C);   // ACCEL_CONFIG
  Wire.write(0x00);   // ±2g
  Wire.endTransmission();

  Serial.println("MPU6500 Ready");
}

void loop() {

  // ================= MPU AUTO DETECTION =================
  // Professional Strict Fall Detection
  readMPU();

  float totalAcc = sqrt(ax*ax + ay*ay + az*az);

  // ===== PHASE 1: FREE FALL (must stay low for 150ms) =====
  static unsigned long lowStartTime = 0;

  if (totalAcc < 0.5) {

    if (lowStartTime == 0) {
      lowStartTime = millis();
    }

    if (millis() - lowStartTime > 50 && !freeFallDetected) {
      freeFallDetected = true;
      freeFallTime = millis();
      Serial.println("Free fall confirmed");
    }

  } else {
    lowStartTime = 0;
  }

  // ===== PHASE 2: IMPACT (within 2s of free fall) =====
  if (freeFallDetected && !impactDetected && (millis() - freeFallTime < 2000)) {

    if (totalAcc > 1.5) {
      impactDetected = true;
      impactTime = millis();
      freeFallDetected = false;
      Serial.println("Impact detected");
    }
  }

  // ===== PHASE 3: IMMOBILITY (stay still for 3 sec after impact) =====
  static unsigned long stillStart = 0;

  if (impactDetected) {

    if (abs(gx) < 30 && abs(gy) < 30 && abs(gz) < 30) {

      if (stillStart == 0) {
        stillStart = millis();
      }

      if (millis() - stillStart > 3000) {

        Serial.println("🚨 REAL FALL CONFIRMED");

        trackingActive = true;
        sendTelegramAlert("🚨 FALL DETECTED");

        impactDetected = false;
        stillStart = 0;
      }

    } else {
      stillStart = 0;  // Movement detected, restart timer
    }

    // Timeout: if 10s pass after impact with no confirmation, reset
    if (millis() - impactTime > 10000) {
      impactDetected = false;
      stillStart = 0;
    }
  }

  // Reset free fall if not followed by impact within 2s
  if (freeFallDetected && (millis() - freeFallTime > 2000)) {
    freeFallDetected = false;
  }

  // ================= READ GPS =================
  while (gpsSerial.available()) {
    gps.encode(gpsSerial.read());
  }

  // ================= BUTTON LOGIC =================
  bool buttonState = digitalRead(SOS_BUTTON);

  // Button Pressed
  if (lastButtonState == HIGH && buttonState == LOW) {
    pressStartTime = millis();
  }

  // Button Released
  if (lastButtonState == LOW && buttonState == HIGH) {

    unsigned long holdDuration = millis() - pressStartTime;

    // STOP (5 sec hold)
    if (holdDuration >= STOP_HOLD_TIME) {

      trackingActive = false;
      autoTriggered = false;
      sendIdleStatus();

      Serial.println("5s HOLD → TRACKING STOPPED");

      sendTelegramAlert("🛑 Tracking Stopped");

      clickCount = 0;
    }
    else {
      clickCount++;
      lastClickTime = millis();
    }
  }

  lastButtonState = buttonState;

  // 3 Click → START
  if (clickCount > 0 && (millis() - lastClickTime > MULTI_CLICK_DELAY)) {

    if (clickCount == 3) {

      trackingActive = true;
      lastTelegramSend = millis();  // Reset telegram timer on SOS start
      Serial.println("3 CLICKS → TRACKING STARTED");

      String message = "🚨 EMERGENCY ALERT 🚨\n";

      if (gps.location.isValid()) {
        lat = gps.location.lat();
        lng = gps.location.lng();

        message += "Location:\n";
        message += "https://maps.google.com/?q=";
        message += String(lat, 6) + "," + String(lng, 6);
      } else {
        message += "GPS not available.";
      }

      sendTelegramAlert(message);
    }

    clickCount = 0;
  }

  // ================= SERIAL COMMANDS =================
  if (Serial.available()) {

    String input = Serial.readStringUntil('\n');
    input.trim();

    if (input == "SOS") {
      trackingActive = true;
      lastTelegramSend = millis();
      Serial.println("Serial → Tracking Started");
    }

    if (input == "STOP") {
      trackingActive = false;
      autoTriggered = false;
      sendIdleStatus();
      Serial.println("Serial → Tracking Stopped");
    }
  }

  // ================= FIREBASE TRACKING =================
  if (trackingActive && millis() - lastSendTime > SEND_INTERVAL) {

    lastSendTime = millis();

    if (gps.location.isValid()) {
      lat = gps.location.lat();
      lng = gps.location.lng();
      sendActiveData();
    }
    else {
      sendActiveWithoutGPS();
    }
  }

  // ================= TELEGRAM PERIODIC UPDATE (every 30s) =================
  if (trackingActive && millis() - lastTelegramSend > TELEGRAM_INTERVAL) {

    lastTelegramSend = millis();

    String message = "📍 Live Tracking Update\n";

    if (gps.location.isValid()) {
      lat = gps.location.lat();
      lng = gps.location.lng();

      message += "https://maps.google.com/?q=";
      message += String(lat, 6) + "," + String(lng, 6);
    } else {
      message += "GPS not available.";
    }

    sendTelegramAlert(message);
  }
}

// ================= READ MPU6500 =================
void readMPU() {

  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x3B);
  Wire.endTransmission(false);
  Wire.requestFrom(MPU_ADDR, 14);

  if (Wire.available() == 14) {

    int16_t ax_raw = Wire.read() << 8 | Wire.read();
    int16_t ay_raw = Wire.read() << 8 | Wire.read();
    int16_t az_raw = Wire.read() << 8 | Wire.read();
    Wire.read(); Wire.read();
    int16_t gx_raw = Wire.read() << 8 | Wire.read();
    int16_t gy_raw = Wire.read() << 8 | Wire.read();
    int16_t gz_raw = Wire.read() << 8 | Wire.read();

    ax = ax_raw / 16384.0;
    ay = ay_raw / 16384.0;
    az = az_raw / 16384.0;

    gx = gx_raw / 131.0;
    gy = gy_raw / 131.0;
    gz = gz_raw / 131.0;
  }
}

// ================= TELEGRAM =================
void sendTelegramAlert(String message) {

  if (WiFi.status() == WL_CONNECTED) {

    for (int i = 0; i < totalContacts; i++) {

      HTTPClient http;

      String url = "https://api.telegram.org/bot" + botToken + "/sendMessage";

      http.begin(url);
      http.addHeader("Content-Type", "application/x-www-form-urlencoded");

      String postData = "chat_id=" + chatIDs[i] + "&text=" + message;

      http.POST(postData);
      http.end();
    }
  }
}

// ================= FIREBASE ACTIVE =================
void sendActiveData() {

  if (WiFi.status() == WL_CONNECTED) {

    HTTPClient http;
    String url = firebaseURL + "/device001.json";

    http.begin(url);
    http.addHeader("Content-Type", "application/json");

    String jsonData = "{";
    jsonData += "\"status\":\"ACTIVE\",";
    jsonData += "\"deviceID\":1,";
    jsonData += "\"lat\":" + String(lat, 6) + ",";
    jsonData += "\"lng\":" + String(lng, 6);
    jsonData += "}";

    int httpResponseCode = http.PUT(jsonData);

    Serial.println(httpResponseCode);

    http.end();
  }
}

// ================= FIREBASE NO GPS =================
void sendActiveWithoutGPS() {

  if (WiFi.status() == WL_CONNECTED) {

    HTTPClient http;
    String url = firebaseURL + "/device001.json";

    http.begin(url);
    http.addHeader("Content-Type", "application/json");

    String jsonData = "{";
    jsonData += "\"status\":\"ACTIVE\",";
    jsonData += "\"deviceID\":1,";
    jsonData += "\"gps\":\"NO_SIGNAL\"";
    jsonData += "}";

    int httpResponseCode = http.PUT(jsonData);

    Serial.println(httpResponseCode);

    http.end();
  }
}

// ================= FIREBASE IDLE =================
void sendIdleStatus() {

  if (WiFi.status() == WL_CONNECTED) {

    HTTPClient http;
    String url = firebaseURL + "/device001.json";

    http.begin(url);
    http.addHeader("Content-Type", "application/json");

    String jsonData = "{";
    jsonData += "\"status\":\"IDLE\",";
    jsonData += "\"deviceID\":1";
    jsonData += "}";

    int httpResponseCode = http.PUT(jsonData);

    Serial.println(httpResponseCode);

    http.end();
  }
}