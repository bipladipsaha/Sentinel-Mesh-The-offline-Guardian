#include <WiFi.h>
#include <HTTPClient.h>
#include <TinyGPS++.h>
#include <HardwareSerial.h>
#include <Wire.h>
#include <SPI.h>
#include <LoRa.h>

// ================= BLE INCLUDES =================
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// ================= BLE GLOBALS =================
BLEServer* pServer = NULL;
BLECharacteristic* pCharacteristic = NULL;
bool deviceConnected = false;

#define SERVICE_UUID        "0000ffe0-0000-1000-8000-00805f9b34fb"
#define CHARACTERISTIC_UUID "0000ffe1-0000-1000-8000-00805f9b34fb"

class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
      deviceConnected = true;
      Serial.println("Sentinel App Connected via BLE!");
    };

    void onDisconnect(BLEServer* pServer) {
      deviceConnected = false;
      Serial.println("Sentinel App Disconnected via BLE!");
      // Restart advertising so the app can reconnect
      BLEDevice::startAdvertising();
    }
};

// ================= WIFI =================
const char* ssid = "iqoo1234";
const char* password = "hello123";

String firebaseURL = "https://esp32iotproject-e9fe1-default-rtdb.asia-southeast1.firebasedatabase.app";

// ================= TELEGRAM =================
String botToken = "8687058189:AAHyYqhE2UAjRLCQLPikGnOt88Uun6rJVVg";

String chatIDs[] = {
  "1206334941",      // Your ID
  "7681145312",      // Contact 2
  "7710246439",      // Anwesha Das
  "7015801586",      // Anisha Majumdar
};

const int totalContacts = 4;

// ================= GPS =================
TinyGPSPlus gps;
HardwareSerial gpsSerial(2);

// ================= LORA =================
#define LORA_SS 13
#define LORA_RST 14
#define LORA_DIO0 26

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

// ================= LEDs =================
#define LED_GREEN 25
#define LED_RED 32

bool wifiReady = false;
bool loraReady = false;
bool mpuReady = false;
bool sosActive = false;

// ================= BUTTON (INTERRUPT) =================
#define SOS_BUTTON 27

volatile bool buttonFlag = false;
volatile unsigned long lastButtonISR = 0;

void IRAM_ATTR buttonISR() {
  // Only trigger if pin is actually LOW (real press) and 1s debounce
  if (digitalRead(SOS_BUTTON) == LOW && millis() - lastButtonISR > 1000) {
    buttonFlag = true;
    lastButtonISR = millis();
  }
}

// ================= TIMERS =================
unsigned long lastSendTime = 0;
const unsigned long SEND_INTERVAL = 5000;

unsigned long lastTelegramSend = 0;
const unsigned long TELEGRAM_INTERVAL = 30000;  // 30 sec

// ================= HTTP TIMEOUT =================
const int HTTP_TIMEOUT = 2000;  // 2 second timeout — keeps loop responsive

// ================= FUNCTION DECLARATIONS =================
void sendActiveData();
void sendActiveWithoutGPS();
void sendIdleStatus();
void sendTelegramAlert(String message);
void sendSOSFlag();
void readMPU();
void sendLoRaSOS(float lat, float lng);
void updateLED();

void setup() {

  Serial.begin(115200);
  gpsSerial.begin(9600, SERIAL_8N1, 16, 17);

  pinMode(SOS_BUTTON, INPUT_PULLUP);
  attachInterrupt(digitalPinToInterrupt(SOS_BUTTON), buttonISR, FALLING);

  pinMode(LED_GREEN, OUTPUT);
  pinMode(LED_RED, OUTPUT);
  digitalWrite(LED_GREEN, LOW);
  digitalWrite(LED_RED, LOW);

  // ================= BLE INITIALIZATION =================
  BLEDevice::init("Sentinel_ESP");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());
  BLEService *pService = pServer->createService(SERVICE_UUID);
  pCharacteristic = pService->createCharacteristic(
                      CHARACTERISTIC_UUID,
                      BLECharacteristic::PROPERTY_READ   |
                      BLECharacteristic::PROPERTY_WRITE  |
                      BLECharacteristic::PROPERTY_NOTIFY |
                      BLECharacteristic::PROPERTY_INDICATE
                    );
  pCharacteristic->addDescriptor(new BLE2902());
  pService->start();
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(false);
  pAdvertising->setMinPreferred(0x0);
  BLEDevice::startAdvertising();
  Serial.println("BLE Ready - Waiting for App Connection");

  WiFi.begin(ssid, password);
  Serial.print("Connecting to WiFi");

  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }

  Serial.println("\nConnected to WiFi");
  wifiReady = true;

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
  mpuReady = true;

  // Initialize LoRa
  SPI.begin(18, 19, 23, LORA_SS);
  LoRa.setPins(LORA_SS, LORA_RST, LORA_DIO0);

  if (!LoRa.begin(433E6)) {
    Serial.println("LoRa init failed! Check wiring.");
    loraReady = false;
  } else {
    Serial.println("LoRa Ready");
    loraReady = true;
  }
}

// ================= STOP HELPER =================
// Call this to immediately stop SOS + update Firebase
void performStop(String source) {
  trackingActive = false;
  sosActive = false;
  autoTriggered = false;
  freeFallDetected = false;
  impactDetected = false;
  Serial.println(source + " → SOS STOPPED");
  sendIdleStatus();
}

// Check for stop signals (button + serial) — call between HTTP operations
void checkForStop() {
  // Check button interrupt
  if (buttonFlag && trackingActive) {
    buttonFlag = false;
    performStop("BTN");
    sendTelegramAlert("🛑 Tracking Stopped");
  }

  // Check serial
  if (Serial.available()) {
    String input = Serial.readStringUntil('\n');
    input.trim();
    input.toUpperCase();
    if (input == "STOP") {
      performStop("Serial");
    }
  }
}

void loop() {

  // ===== PRIORITY #1: CHECK STOP SIGNALS FIRST =====
  if (buttonFlag) {
    buttonFlag = false;

    if (trackingActive) {
      // TURN OFF SOS
      performStop("BTN");
      sendTelegramAlert("🛑 Tracking Stopped");
    } else {
      // TURN ON SOS
      trackingActive = true;
      sosActive = true;
      lastTelegramSend = millis();
      Serial.println("BTN: SOS ON");

      // === TRIGGER PHONE RECORDING VIA BLE ===
      if (deviceConnected) {
        pCharacteristic->setValue("2"); // 2 = Button SOS
        pCharacteristic->notify();
        delay(100);
        pCharacteristic->setValue("0"); // Clear the trigger
        Serial.println("BLE: Instructed phone to record");
      }

      String message = "🚨 EMERGENCY ALERT 🚨\n";

      if (gps.location.isValid()) {
        lat = gps.location.lat();
        lng = gps.location.lng();
        message += "Location:\n";
        message += "https://maps.google.com/?q=";
        message += String(lat, 6) + "," + String(lng, 6);
        sendActiveData();
      } else {
        message += "GPS not available.";
        sendActiveWithoutGPS();
      }

      sendTelegramAlert(message);
      sendLoRaSOS(lat, lng);
    }
  }

  // ===== PRIORITY #2: SERIAL COMMANDS =====
  if (Serial.available()) {
    String input = Serial.readStringUntil('\n');
    input.trim();
    input.toUpperCase();

    Serial.println("Serial RX: [" + input + "]");

    if (input == "SOS") {
      trackingActive = true;
      sosActive = true;
      lastTelegramSend = millis();
      sendActiveWithoutGPS();
      Serial.println("Serial → Tracking Started");
      
      // === TRIGGER PHONE RECORDING VIA BLE ===
      if (deviceConnected) {
        pCharacteristic->setValue("2"); // Using 2 for manual serial trigger as well
        pCharacteristic->notify();
        delay(100);
        pCharacteristic->setValue("0"); // Clear the trigger
      }
    }

    if (input == "STOP") {
      performStop("Serial");
    }
  }

  // If stopped, skip everything else
  if (!trackingActive) {
    // Still read GPS and MPU in idle
    while (gpsSerial.available()) { gps.encode(gpsSerial.read()); }
    readMPU();
    updateLED();

    // ===== FALL/IMPACT DETECTION (only when NOT tracking) =====
    float totalAcc = sqrt(ax*ax + ay*ay + az*az);

    // PHASE 1: Detect hard impact/shake (acc > 2.0g)
    if (!impactDetected && totalAcc > 2.0) {
      impactDetected = true;
      impactTime = millis();
      Serial.println("💥 Impact/shake detected! Acc=" + String(totalAcc, 2));
    }

    // PHASE 2: After impact, check for stillness (hold still for 2 seconds)
    static unsigned long stillStart = 0;
    if (impactDetected) {
      if (abs(gx) < 50 && abs(gy) < 50 && abs(gz) < 50 && totalAcc < 1.5) {
        if (stillStart == 0) {
          stillStart = millis();
          Serial.println("⏳ Stillness started... hold still 2s");
        }
        if (millis() - stillStart > 2000) {
          Serial.println("🚨 FALL CONFIRMED — SOS TRIGGERED");
          sosActive = true;
          trackingActive = true;

          // === TRIGGER PHONE RECORDING VIA BLE ===
          if (deviceConnected) {
            pCharacteristic->setValue("1"); // 1 = Impact SOS
            pCharacteristic->notify();
            delay(100);
            pCharacteristic->setValue("0"); // Clear the trigger
            Serial.println("BLE: Instructed phone to record (IMPACT)");
          }

          sendActiveWithoutGPS();
          sendTelegramAlert("🚨 FALL DETECTED");
          sendLoRaSOS(lat, lng);
          impactDetected = false;
          stillStart = 0;
        }
      } else {
        if (stillStart != 0) Serial.println("❌ Movement detected, resetting...");
        stillStart = 0;
      }

      // Timeout: 10s after impact without confirmation → reset
      if (millis() - impactTime > 10000) {
        Serial.println("⏰ Impact timeout, resetting");
        impactDetected = false;
        stillStart = 0;
      }
    }

    return;  // Skip tracking logic below
  }

  // ================= TRACKING IS ACTIVE =================

  // Read GPS
  while (gpsSerial.available()) { gps.encode(gpsSerial.read()); }
  readMPU();

  // Firebase tracking (every 5s)
  if (millis() - lastSendTime > SEND_INTERVAL) {
    checkForStop();  // Check stop before HTTP call
    if (!trackingActive) return;

    lastSendTime = millis();
    if (gps.location.isValid()) {
      lat = gps.location.lat();
      lng = gps.location.lng();
      sendActiveData();
    } else {
      sendActiveWithoutGPS();
    }
  }

  // Telegram periodic (every 30s)
  if (trackingActive && millis() - lastTelegramSend > TELEGRAM_INTERVAL) {
    checkForStop();  // Check stop before HTTP call
    if (!trackingActive) return;

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

  // LED update
  updateLED();
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

// ================= LED STATUS (NON-BLOCKING) =================
void updateLED() {
  static unsigned long lastBlinkTime = 0;
  static bool ledState = false;

  if (sosActive) {
    digitalWrite(LED_GREEN, LOW);
    if (millis() - lastBlinkTime > 200) {
      lastBlinkTime = millis();
      ledState = !ledState;
      digitalWrite(LED_RED, ledState ? HIGH : LOW);
    }
  } else {
    digitalWrite(LED_RED, LOW);
    if (wifiReady && loraReady && mpuReady) {
      digitalWrite(LED_GREEN, HIGH); 
    } else {
      digitalWrite(LED_GREEN, LOW);
    }
  }
}

// ================= LORA SOS =================
void sendLoRaSOS(float lat, float lng) {
  Serial.println("Preparing LoRa packet...");
  String packet = "SOS," + String(lat, 6) + "," + String(lng, 6);
  LoRa.beginPacket();
  LoRa.print(packet);
  LoRa.endPacket();
  Serial.println("LoRa TX → " + packet);
}

// ================= TELEGRAM (WITH TIMEOUT) =================
void sendTelegramAlert(String message) {
  if (WiFi.status() == WL_CONNECTED) {
    message.replace("\n", "\\n");
    for (int i = 0; i < totalContacts; i++) {
      HTTPClient http;
      String url = "https://api.telegram.org/bot" + botToken + "/sendMessage";
      http.setTimeout(HTTP_TIMEOUT);
      http.begin(url);
      http.addHeader("Content-Type", "application/json");
      String postData = "{\"chat_id\":\"" + chatIDs[i] + "\", \"text\":\"" + message + "\"}";
      int code = http.POST(postData);
      Serial.println("Telegram [" + String(i) + "] → " + String(code));
      http.end();
    }
  }
}

// ================= FIREBASE ACTIVE (WITH TIMEOUT) =================
void sendActiveData() {
  if (WiFi.status() == WL_CONNECTED) {
    HTTPClient http;
    String url = firebaseURL + "/device001.json";
    http.setTimeout(HTTP_TIMEOUT);
    http.begin(url);
    http.addHeader("Content-Type", "application/json");
    String jsonData = "{";
    jsonData += "\"status\":\"ACTIVE\",";
    jsonData += "\"deviceID\":1,";
    jsonData += "\"lat\":" + String(lat, 6) + ",";
    jsonData += "\"lng\":" + String(lng, 6);
    jsonData += "}";
    int httpResponseCode = http.PUT(jsonData);
    Serial.println("Firebase → " + String(httpResponseCode));
    http.end();
  }
}

// ================= FIREBASE NO GPS (WITH TIMEOUT) =================
void sendActiveWithoutGPS() {
  if (WiFi.status() == WL_CONNECTED) {
    HTTPClient http;
    String url = firebaseURL + "/device001.json";
    http.setTimeout(HTTP_TIMEOUT);
    http.begin(url);
    http.addHeader("Content-Type", "application/json");
    String jsonData = "{";
    jsonData += "\"status\":\"ACTIVE\",";
    jsonData += "\"deviceID\":1,";
    jsonData += "\"gps\":\"NO_SIGNAL\"";
    jsonData += "}";
    int httpResponseCode = http.PUT(jsonData);
    Serial.println("Firebase → " + String(httpResponseCode));
    http.end();
  }
}

// ================= FIREBASE IDLE (WITH TIMEOUT) =================
void sendIdleStatus() {
  if (WiFi.status() == WL_CONNECTED) {
    HTTPClient http;
    String url = firebaseURL + "/device001.json";
    http.setTimeout(HTTP_TIMEOUT);
    http.begin(url);
    http.addHeader("Content-Type", "application/json");
    String jsonData = "{";
    jsonData += "\"status\":\"IDLE\",";
    jsonData += "\"deviceID\":1";
    jsonData += "}";
    int httpResponseCode = http.PUT(jsonData);
    Serial.println("Firebase → " + String(httpResponseCode));
    http.end();
  }
}
