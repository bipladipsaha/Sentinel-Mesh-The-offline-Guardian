/*
 * ============================================================
 *  ESP32 Tracker — WiFi + GPS + Button + MPU6500
 * ============================================================
 *
 *  Features:
 *    - WiFi connection
 *    - GPS location tracking (TinyGPS++)
 *    - SOS button (3-click start, 5-sec hold stop)
 *    - MPU6500 fall detection (free-fall → impact → immobility)
 *
 *  Wiring:
 *    GPS TX  → GPIO 16 (RX2)
 *    GPS RX  → GPIO 17 (TX2)
 *    SOS Btn → GPIO 14 (active LOW, internal pull-up)
 *    MPU SDA → GPIO 21
 *    MPU SCL → GPIO 22
 * ============================================================
 */

#include <WiFi.h>
#include <TinyGPS++.h>
#include <HardwareSerial.h>
#include <Wire.h>

// ──────────────────────────────────────────────
//  WiFi Credentials
// ──────────────────────────────────────────────
const char* ssid     = "iqoo1234";
const char* password = "hello123";

// ──────────────────────────────────────────────
//  GPS
// ──────────────────────────────────────────────
TinyGPSPlus gps;
HardwareSerial gpsSerial(2);          // UART2: RX=16, TX=17

// ──────────────────────────────────────────────
//  MPU6500  (I2C address 0x68)
// ──────────────────────────────────────────────
#define MPU_ADDR 0x68

float ax, ay, az;                     // accelerometer (g)
float gx, gy, gz;                     // gyroscope     (°/s)

bool           freeFallDetected = false;
unsigned long  freeFallTime     = 0;
bool           impactDetected   = false;
unsigned long  impactTime       = 0;

// ──────────────────────────────────────────────
//  Tracking State
// ──────────────────────────────────────────────
bool  trackingActive = false;
float lat = 0.0;
float lng = 0.0;

// ──────────────────────────────────────────────
//  Button  (GPIO 14, active LOW)
// ──────────────────────────────────────────────
#define SOS_BUTTON 14

bool           lastButtonState = HIGH;
unsigned long  pressStartTime  = 0;
int            clickCount      = 0;
unsigned long  lastClickTime   = 0;

const unsigned long MULTI_CLICK_DELAY = 600;   // ms window for multi-click
const unsigned long STOP_HOLD_TIME    = 5000;  // 5 s hold → stop

// ──────────────────────────────────────────────
//  Forward Declarations
// ──────────────────────────────────────────────
void readMPU();

// ============================================================
//  SETUP
// ============================================================
void setup() {

  Serial.begin(115200);
  gpsSerial.begin(9600, SERIAL_8N1, 16, 17);

  pinMode(SOS_BUTTON, INPUT_PULLUP);

  // — Connect to WiFi —
  WiFi.begin(ssid, password);
  Serial.print("Connecting to WiFi");

  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }

  Serial.println("\nConnected to WiFi");

  // — Initialize MPU6500 —
  Wire.begin(21, 22);
  Wire.setClock(100000);

  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x6B);                   // PWR_MGMT_1 register
  Wire.write(0x00);                   // wake up
  Wire.endTransmission();

  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x1C);                   // ACCEL_CONFIG register
  Wire.write(0x00);                   // ±2 g range
  Wire.endTransmission();

  Serial.println("MPU6500 Ready");
}

// ============================================================
//  LOOP
// ============================================================
void loop() {

  // ── 1. MPU Fall Detection ──────────────────
  readMPU();

  float totalAcc = sqrt(ax * ax + ay * ay + az * az);

  // Phase 1 — Free-fall (accel stays < 0.5 g for 50 ms)
  static unsigned long lowStartTime = 0;

  if (totalAcc < 0.5) {

    if (lowStartTime == 0) lowStartTime = millis();

    if (millis() - lowStartTime > 50 && !freeFallDetected) {
      freeFallDetected = true;
      freeFallTime = millis();
      Serial.println("Free fall confirmed");
    }

  } else {
    lowStartTime = 0;
  }

  // Phase 2 — Impact (> 1.5 g within 2 s of free-fall)
  if (freeFallDetected && !impactDetected && (millis() - freeFallTime < 2000)) {

    if (totalAcc > 1.5) {
      impactDetected   = true;
      impactTime       = millis();
      freeFallDetected = false;
      Serial.println("Impact detected");
    }
  }

  // Phase 3 — Immobility (gyro stays low for 3 s after impact)
  static unsigned long stillStart = 0;

  if (impactDetected) {

    if (abs(gx) < 30 && abs(gy) < 30 && abs(gz) < 30) {

      if (stillStart == 0) stillStart = millis();

      if (millis() - stillStart > 3000) {
        Serial.println("REAL FALL CONFIRMED");
        trackingActive = true;
        impactDetected = false;
        stillStart     = 0;
      }

    } else {
      stillStart = 0;                 // movement → restart timer
    }

    // Timeout: 10 s with no confirmation → reset
    if (millis() - impactTime > 10000) {
      impactDetected = false;
      stillStart     = 0;
    }
  }

  // Reset free-fall if no impact within 2 s
  if (freeFallDetected && (millis() - freeFallTime > 2000)) {
    freeFallDetected = false;
  }

  // ── 2. Read GPS data ──────────────────────
  while (gpsSerial.available()) {
    gps.encode(gpsSerial.read());
  }

  if (gps.location.isValid()) {
    lat = gps.location.lat();
    lng = gps.location.lng();
  }

  // ── 3. Button handling ────────────────────
  bool buttonState = digitalRead(SOS_BUTTON);

  // Detect press (HIGH → LOW)
  if (lastButtonState == HIGH && buttonState == LOW) {
    pressStartTime = millis();
  }

  // Detect release (LOW → HIGH)
  if (lastButtonState == LOW && buttonState == HIGH) {

    unsigned long holdDuration = millis() - pressStartTime;

    if (holdDuration >= STOP_HOLD_TIME) {
      // 5-second hold → STOP tracking
      trackingActive = false;
      Serial.println("5 s HOLD  →  TRACKING STOPPED");
      clickCount = 0;

    } else {
      // Short press → count clicks
      clickCount++;
      lastClickTime = millis();
    }
  }

  lastButtonState = buttonState;

  // Evaluate multi-click after delay window
  if (clickCount > 0 && (millis() - lastClickTime > MULTI_CLICK_DELAY)) {

    if (clickCount == 3) {
      trackingActive = true;
      Serial.println("3 CLICKS  →  TRACKING STARTED");
    }

    clickCount = 0;
  }

  // ── 4. Serial output while tracking ───────
  if (trackingActive) {

    static unsigned long lastPrint = 0;

    if (millis() - lastPrint > 5000) {
      lastPrint = millis();

      if (gps.location.isValid()) {
        Serial.print("GPS: ");
        Serial.print(lat, 6);
        Serial.print(", ");
        Serial.println(lng, 6);
      } else {
        Serial.println("GPS: NO SIGNAL");
      }
    }
  }
}

// ============================================================
//  READ MPU6500 — fetch accel & gyro over I2C
// ============================================================
void readMPU() {

  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x3B);                   // start at ACCEL_XOUT_H
  Wire.endTransmission(false);
  Wire.requestFrom(MPU_ADDR, 14);

  if (Wire.available() == 14) {

    int16_t ax_raw = Wire.read() << 8 | Wire.read();
    int16_t ay_raw = Wire.read() << 8 | Wire.read();
    int16_t az_raw = Wire.read() << 8 | Wire.read();

    Wire.read(); Wire.read();         // skip temperature

    int16_t gx_raw = Wire.read() << 8 | Wire.read();
    int16_t gy_raw = Wire.read() << 8 | Wire.read();
    int16_t gz_raw = Wire.read() << 8 | Wire.read();

    ax = ax_raw / 16384.0;           // ±2 g → 16384 LSB/g
    ay = ay_raw / 16384.0;
    az = az_raw / 16384.0;

    gx = gx_raw / 131.0;             // ±250 °/s → 131 LSB/(°/s)
    gy = gy_raw / 131.0;
    gz = gz_raw / 131.0;
  }
}
