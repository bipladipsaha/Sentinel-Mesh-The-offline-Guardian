#include <WiFi.h>

const char* ssid = "iqoo1234";
const char* password = "hello123";

void setup() {
  Serial.begin(115200);

  WiFi.begin(ssid, password);

  while(WiFi.status() != WL_CONNECTED){
    delay(1000);
    Serial.println("Connecting...");
  }

  Serial.println("WiFi Connected");
}

void loop(){}