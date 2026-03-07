# 🚨 Sentinel Mesh – Smart Women Safety System

Sentinel Mesh is a multi-layer IoT-based women safety system designed to provide real-time emergency detection, location tracking, and rapid alert transmission.

The system combines hardware sensors, cloud infrastructure, LoRa communication, and a mobile application to ensure that emergency alerts can reach trusted contacts as well as nearby users.

It provides multiple communication channels so that emergency alerts can still be transmitted even if one network fails.

---

## 📌 Project Overview

Women often face safety risks when traveling alone or in unfamiliar areas. Sentinel Mesh addresses this problem by providing a smart wearable safety device capable of:

- Detecting dangerous situations automatically
- Sending emergency alerts with location
- Broadcasting emergency signals through multiple networks
- Alerting nearby users through a mobile app
- Recording audio/video evidence during emergencies

The system ensures fast response and improved safety through redundant communication technologies.

---

## 🎯 Key Features

### 🚨 SOS Emergency Trigger
- Activated by pressing the SOS button three times
- Sends alerts to predefined contacts
- Starts live location tracking
- Notifies nearby users through the mobile application

### 🧍‍♀️ Intelligent Fall Detection
The system uses an MPU6500 accelerometer and gyroscope to detect falls.

Three-step detection process:
1. Free fall detection
2. Impact detection
3. Immobility confirmation

If all conditions are met, the system automatically triggers an emergency alert.

### 📍 GPS Location Tracking
A NEO-6M GPS module provides real-time location tracking.

**Example coordinates:**
- Latitude: 22.5726
- Longitude: 88.3639

**Location is shared via:**
- Firebase cloud database
- Telegram alerts
- Nearby SOS notifications
- Google Maps links

### 🌐 Cloud Monitoring System
Emergency data is stored in Firebase Realtime Database.

This enables:
- Live monitoring
- Remote tracking
- Mobile application integration
- Cloud-based analytics

**Example database entry:**
```json
"device001": {
  "status": "ACTIVE",
  "deviceID": 1,
  "lat": 22.5726,
  "lng": 88.3639
}
```

### 📩 Telegram Emergency Alerts
When an emergency occurs, the system automatically sends messages to emergency contacts.

**Example alert:**
> 🚨 EMERGENCY ALERT
> 
> Location:
> [https://maps.google.com/?q=22.5726,88.3639](https://maps.google.com/?q=22.5726,88.3639)

This allows contacts to instantly view the victim’s location.

### 📡 LoRa Long-Range Emergency Communication
The system includes LoRa (SX1278) as a backup communication channel.

**Advantages:**
- Works without internet
- Long-range communication
- Emergency signal broadcast

**Example LoRa packet:**
`SOS,22.5726,88.3639`

This packet can be received by LoRa gateways several kilometers away.

### 📱 Mobile Safety Application
Sentinel Mesh includes a mobile application that enables community-based emergency response.

The application allows nearby users to receive SOS alerts with location information.

### 🌍 Nearby SOS Notification System
When SOS is triggered:
1. ESP32 sends victim location to Firebase
2. Cloud server identifies nearby users
3. Nearby phones receive push notifications

**System flow:**
```text
ESP32 Device
      │
      │ WiFi
      ▼
Firebase Cloud Server
      │
      │ Identify nearby users
      ▼
Mobile App Users
      │
      ▼
SOS Notification + Location
```

**Example notification:**
> 🚨 SOS ALERT
> 
> A person nearby needs help.
> 
> Location: 22.5726, 88.3639
> 
> [Open Map] (Opens directly in Google Maps)

### 🎥 Audio & Video Evidence Recording
The mobile app can automatically start recording:
- 📹 Video
- 🎤 Audio

when an SOS alert is received.

This helps capture potential evidence during dangerous situations.

Recorded data can be:
- Stored locally
- Uploaded to cloud storage
- Shared with authorities

---

## 🧠 System Architecture

```text
Women Safety Device
        │
        ▼
ESP32 Controller
│
├ GPS Module (NEO-6M)
├ MPU6500 Motion Sensor
├ SOS Button
├ Status LED
│
├ WiFi → Firebase Database
│         │
│         ▼
│   Nearby User Detection
│         │
│         ▼
│   Mobile App Notification
│
├ Telegram Alerts
└ LoRa Emergency Broadcast
```

---

## ⚙️ Hardware Components

| Component | Purpose |
| :--- | :--- |
| ESP32 | Main microcontroller |
| NEO-6M GPS | Real-time location tracking |
| MPU6500 | Fall detection |
| LoRa SX1278 (Ra-02) | Long-range emergency communication |
| SOS Button | Manual emergency trigger |
| LED Indicator | System status display |
| 220Ω Resistor | LED protection |
| LoRa Antenna | Radio signal transmission |

---

## 🔌 Hardware Connections

### GPS Module
| GPS | ESP32 |
| :--- | :--- |
| VCC | 3.3V |
| GND | GND |
| TX | GPIO16 |
| RX | GPIO17 |

### MPU6500
| MPU6500 | ESP32 |
| :--- | :--- |
| VCC | 3.3V |
| GND | GND |
| SDA | GPIO21 |
| SCL | GPIO22 |

### LoRa Module (SX1278)
| LoRa | ESP32 |
| :--- | :--- |
| VCC | 3.3V |
| GND | GND |
| SCK | GPIO18 |
| MISO | GPIO19 |
| MOSI | GPIO23 |
| NSS | GPIO5 |
| RESET | GPIO14 |
| DIO0 | GPIO26 |

> ⚠️ Always connect the antenna before powering the LoRa module.

### SOS Button
| Button | ESP32 |
| :--- | :--- |
| Pin | GPIO27 |
| Other | GND |

*(Uses internal pull-up resistor)*

### Status LED
| LED | ESP32 |
| :--- | :--- |
| Anode | GPIO25 |
| Cathode | GND |

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

---

✅ *If you want, I can also help you add three powerful sections that make a GitHub project look very professional:*
- *📊 System Architecture Diagram*
- *🔄 Project Workflow Diagram*
- *📸 Project Images Section*

*These make your repository much stronger for hackathons and reviewers.*
