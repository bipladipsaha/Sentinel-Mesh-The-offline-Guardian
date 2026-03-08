# 🚨 Sentinel Mesh – Smart Women Safety System

Sentinel Mesh is a **multi-layer IoT-based women safety system** designed to provide **real-time emergency detection, location tracking, and rapid alert transmission**.

The system combines **hardware sensors, cloud infrastructure, LoRa communication, and a mobile application** to ensure that emergency alerts can reach **trusted contacts as well as nearby users**.

It provides **multiple communication channels** so that emergency alerts can still be transmitted even if one network fails.

---

# 📌 Project Overview

Women often face safety risks when traveling alone or in unfamiliar areas. Sentinel Mesh addresses this problem by providing a **smart wearable safety device** capable of:

- Detecting dangerous situations automatically
- Sending emergency alerts with location
- Broadcasting emergency signals through multiple networks
- Alerting nearby users through a mobile app
- Recording audio/video evidence during emergencies

The system ensures **fast response and improved safety** through **redundant communication technologies**.

---

# 🎯 Key Features

## 🚨 SOS Emergency Trigger

- Activated by pressing the **SOS button three times**
- Sends alerts to predefined contacts
- Starts **live location tracking**
- Notifies nearby users through the mobile application

---

## 🧍‍♀️ Intelligent Fall Detection

The system uses an **MPU6500 accelerometer and gyroscope** to detect falls.

### Three-step detection process:

1. Free fall detection
2. Impact detection
3. Immobility confirmation

If all conditions are met, the system **automatically triggers an emergency alert**.

---

## � GPS Location Tracking

A **NEO-6M GPS module** provides real-time location tracking.

---

## 💡 LED Status Indicators

| LED State | Meaning |
| :--- | :--- |
| OFF | Device starting |
| ON | System ready |
| Blinking | Emergency triggered |

---

## 🖥 Software Requirements

**Development Environment:**
- Arduino IDE

**Required Libraries:**
*(Install from Arduino Library Manager)*
- WiFi.h
- HTTPClient.h
- TinyGPS++
- Wire.h
- SPI.h
- LoRa.h

---

## 🚀 System Workflow

**Device Startup:**
Power ON ➔ Initialize sensors ➔ Connect to WiFi ➔ Start LoRa module ➔ System Ready

**Fall Detection Workflow:**
Free Fall Detected ➔ Impact Detected ➔ Immobility Confirmed ➔ Emergency Alert Triggered

**SOS Button Workflow:**
User presses SOS (3 clicks) ➔ Telegram alert sent ➔ Firebase updated ➔ Nearby users notified ➔ LoRa emergency broadcast

**Stop Tracking:**
Holding the SOS button for 5 seconds stops tracking.

---

## 🔐 Reliability & Safety

The system uses multiple communication channels to ensure alerts are transmitted even if one network fails.

**Communication layers:**
1. WiFi → Cloud alerts
2. LoRa → Long-range emergency broadcast
3. Mobile App → Nearby community alert

---

## 🛠 Future Improvements

Possible future upgrades:
- 📱 Dedicated mobile app UI
- 🎥 Live video streaming
- 🔊 Emergency buzzer alarm
- 🛰 GSM module for independent internet connectivity
- 📡 LoRa mesh network
- 🔋 Battery level monitoring
- ☁ Cloud analytics dashboard

---

## 👩‍💻 Contributors

This project was developed by:
- **Bipladip Saha** – Hardware Integration & ESP32 Programming
- **Anisha Majumdar** – Sensor Integration & Fall Detection System
- **Anwesha Das** – Cloud Integration & Firebase Alert System
- **Bittu Sharma** – Mobile Application Development & Nearby SOS Alert System

---

## 📜 License

This project is developed for academic and research purposes.


## 🎥 Project Demo Video

Watch the working demonstration of the Sentinel Mesh safety system:

🔗 https://drive.google.com/file/d/16RE3Yvbk_A_8LJmS1GmmqQPxhe8BqOlp/view?usp=drivesdk