#include <WiFi.h>
#include <TinyGPS++.h>
#include <HardwareSerial.h>

const char* ssid = "iqoo1234";
const char* password = "hello123";

TinyGPSPlus gps;
HardwareSerial gpsSerial(2);

#define SOS_BUTTON 14

bool trackingActive = false;

void setup() {

  Serial.begin(115200);

  pinMode(SOS_BUTTON, INPUT_PULLUP);

  WiFi.begin(ssid, password);

  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
  }

  Serial.println("WiFi Connected");

  gpsSerial.begin(9600, SERIAL_8N1, 16, 17);
}

void loop() {

  while (gpsSerial.available()) {
    gps.encode(gpsSerial.read());
  }

  if (digitalRead(SOS_BUTTON) == LOW) {

    trackingActive = !trackingActive;
    delay(500);

    if (trackingActive) {
      Serial.println("SOS Activated");
    } else {
      Serial.println("Tracking Stopped");
    }
  }

  if (trackingActive && gps.location.isValid()) {

    Serial.print("Latitude: ");
    Serial.println(gps.location.lat(), 6);

    Serial.print("Longitude: ");
    Serial.println(gps.location.lng(), 6);
  }
}
