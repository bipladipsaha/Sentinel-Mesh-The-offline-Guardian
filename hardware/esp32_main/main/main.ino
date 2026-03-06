#include <WiFi.h>
#include <TinyGPS++.h>
#include <HardwareSerial.h>

// WiFi
const char* ssid = "iqoo1234";
const char* password = "hello123";

// GPS
TinyGPSPlus gps;
HardwareSerial gpsSerial(2);

void setup() {

  Serial.begin(115200);

  // WiFi
  Serial.println("Connecting to WiFi...");
  WiFi.begin(ssid, password);

  while (WiFi.status() != WL_CONNECTED) {
    delay(1000);
    Serial.println("Connecting...");
  }

  Serial.println("WiFi Connected");

  // GPS
  gpsSerial.begin(9600, SERIAL_8N1, 16, 17);
  Serial.println("GPS Module Initialized");
}

void loop() {

  while (gpsSerial.available()) {
    gps.encode(gpsSerial.read());
  }

  if (gps.location.isUpdated()) {

    Serial.print("Latitude: ");
    Serial.println(gps.location.lat(), 6);

    Serial.print("Longitude: ");
    Serial.println(gps.location.lng(), 6);

    Serial.println("-------------------");
  }
}