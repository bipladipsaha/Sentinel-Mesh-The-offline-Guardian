#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

BLEServer* pServer = NULL;
BLECharacteristic* pCharacteristic = NULL;
bool deviceConnected = false;

// Sentinel BLE UUIDs
#define SERVICE_UUID        "0000ffe0-0000-1000-8000-00805f9b34fb"
#define CHARACTERISTIC_UUID "0000ffe1-0000-1000-8000-00805f9b34fb"

// Pins
const int BUTTON_PIN = 4;
const int IMPACT_SENSOR_PIN = 5;

// State tracking to prevent bouncing
int lastButtonState = HIGH;
int lastImpactState = HIGH;

class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
      deviceConnected = true;
      Serial.println("Sentinel App Connected!");
    };

    void onDisconnect(BLEServer* pServer) {
      deviceConnected = false;
      Serial.println("Sentinel App Disconnected!");
      // Restart advertising so the app can reconnect
      BLEDevice::startAdvertising();
    }
};

void setup() {
  Serial.begin(115200);
  pinMode(BUTTON_PIN, INPUT_PULLUP);
  pinMode(IMPACT_SENSOR_PIN, INPUT_PULLUP);

  // Initialize BLE
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
  
  Serial.println("Waiting for Sentinel App to connect...");
}

void loop() {
  if (deviceConnected) {
    int currentButtonState = digitalRead(BUTTON_PIN);
    int currentImpactState = digitalRead(IMPACT_SENSOR_PIN);

    // If button pressed (LOW state due to INPUT_PULLUP)
    if (currentButtonState == LOW && lastButtonState == HIGH) {
      Serial.println("SOS Button Pressed! Sending alert...");
      pCharacteristic->setValue("2");
      pCharacteristic->notify();
      delay(1000); // Debounce
    }
    lastButtonState = currentButtonState;

    // If impact detected
    if (currentImpactState == LOW && lastImpactState == HIGH) {
      Serial.println("Impact Detected! Sending alert...");
      pCharacteristic->setValue("1");
      pCharacteristic->notify();
      delay(1000); // Debounce
    }
    lastImpactState = currentImpactState;
  }
  
  delay(50);
}
