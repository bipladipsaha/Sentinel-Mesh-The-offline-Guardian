/*
 * ============================================================
 *  ESP32 Tracker — WiFi + GPS + Button Only
 * ============================================================
 *
 *  Features:
 *    - WiFi connection
 *    - GPS location tracking (TinyGPS++)
 *    - SOS button (3-click start, 5-sec hold stop)
 *
 *  Wiring:
 *    GPS TX → GPIO 16 (RX2)
 *    GPS RX → GPIO 17 (TX2)
 *    SOS Button → GPIO 14 (active LOW, internal pull-up)
 * ============================================================
 */

#include <WiFi.h>
#include <TinyGPS++.h>
#include <HardwareSerial.h>

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
}

// ============================================================
//  LOOP
// ============================================================
void loop() {

  // ── Read GPS data ──────────────────────────
  while (gpsSerial.available()) {
    gps.encode(gpsSerial.read());
  }

  // ── Update coordinates if GPS has a fix ────
  if (gps.location.isValid()) {
    lat = gps.location.lat();
    lng = gps.location.lng();
  }

  // ── Button handling ────────────────────────
  bool buttonState = digitalRead(SOS_BUTTON);

  // Detect press (HIGH → LOW)
  if (lastButtonState == HIGH && buttonState == LOW) {
    pressStartTime = millis();
  }

  // Detect release (LOW → HIGH)
  if (lastButtonState == LOW && buttonState == HIGH) {

    unsigned long holdDuration = millis() - pressStartTime;

    if (holdDuration >= STOP_HOLD_TIME) {
      // ── 5-second hold → STOP tracking ──
      trackingActive = false;
      Serial.println("5 s HOLD  →  TRACKING STOPPED");
      clickCount = 0;

    } else {
      // ── Short press → count clicks ──
      clickCount++;
      lastClickTime = millis();
    }
  }

  lastButtonState = buttonState;

  // ── Evaluate multi-click after delay window ──
  if (clickCount > 0 && (millis() - lastClickTime > MULTI_CLICK_DELAY)) {

    if (clickCount == 3) {
      // ── 3 clicks → START tracking ──
      trackingActive = true;
      Serial.println("3 CLICKS  →  TRACKING STARTED");
    }

    clickCount = 0;
  }

  // ── Print GPS to Serial when tracking ──────
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