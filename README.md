## Project Overview

The Women Safety System is an IoT-based emergency device built using ESP32.  
It detects dangerous situations using a manual SOS button or automatic fall detection and provides real-time GPS tracking.

The system can later send alerts and location data to authorities, nearby users, or emergency contacts.
## Features

- Real-time GPS tracking using NEO-6M
- SOS emergency button trigger
- Triple-click to start emergency tracking
- 5-second hold to stop tracking
- Fall detection using MPU6500 / MPU6050
- WiFi connectivity for data transmission
- Long-range communication using LoRa
## Wiring Connections

| Component | ESP32 Pin |
|----------|-----------|
| GPS TX | GPIO 16 |
| GPS RX | GPIO 17 |
| SOS Button | GPIO 14 |
## Libraries Used

- WiFi.h
- TinyGPS++
- Wire.h
- HardwareSerial
## Contributors

- Bipladip Saha
- Anisha Majumdar
- Anwesha Das
- Bittu Sharma

\## Required Hardware Video \[Watch the Required Hardware Demo](https://drive.google.com/file/d/1sznElylcTeHZ-qqQ0SUWzSZHo2gCIUsY/view?usp=drivesdk)