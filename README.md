# 🌱 GreenGuard AI

### AI + IoT Smart Farming Platform for Lettuce Disease Detection, Crop Monitoring, Drone-Assisted Scanning, and E-commerce

GreenGuard AI is a full-stack undergraduate capstone project that combines **Artificial Intelligence**, **Internet of Things (IoT)**, **Mobile Development**, **Web Technologies**, **Computer Vision**, and **Smart Farming** into a single integrated ecosystem.

The platform is designed specifically for lettuce farming. It allows farmers to monitor crops, detect lettuce diseases using AI, capture crop images using an ESP32-CAM, monitor environmental conditions, manage products, receive customer orders in real time, and sell directly to buyers through an integrated e-commerce system.

GreenGuard AI is also being developed toward autonomous drone-assisted crop monitoring, where a drone can navigate lettuce-growing areas, capture crop images, send them for AI analysis, and return disease results to the farmer application.

---

# 🚀 Project Overview

GreenGuard AI connects several major components through **Supabase** and the GreenGuard AI server.

```text
                         GreenGuard AI Ecosystem

                    ┌─────────────────────────┐
                    │      Buyer Website      │
                    │        Next.js          │
                    └────────────┬────────────┘
                                 │
                           Browse / Orders
                                 │
                                 ▼
                       ┌───────────────────┐
                       │     Supabase      │
                       │───────────────────│
                       │ Authentication    │
                       │ PostgreSQL        │
                       │ Storage           │
                       │ Realtime          │
                       │ Row Level Security│
                       └─────────┬─────────┘
                                 │
                ┌────────────────┴────────────────┐
                │                                 │
                ▼                                 ▼

       Farmer Mobile App                  Admin Dashboard
           Flutter                           Next.js

                │
                │ Camera / Monitoring
                ▼

           ESP32-CAM
                │
                ▼
        GreenGuard AI Server
                │
                ▼
        Image Enhancement
                │
                ▼
       Subject Identification
                │
                ▼
          YOLOv8 Detection
                │
                ▼
       Lettuce Health Result
                │
                ▼
        Farmer Mobile App
                │
                ▼
        Diagnostic History
```

---

# 📱 Farmer Mobile Application

The main farmer application is developed using **Flutter**.

It serves as the primary interface used by farmers to access crop monitoring, AI disease diagnosis, products, customer orders, notifications, weather information, and IoT features.

## Features

- Secure Authentication
- Role-based Authentication
- Farmer Dashboard
- Product Management
- Add / Edit / Delete Crops
- Product Image Upload
- Order Management
- Order Status Updates
- Delivery / Pickup Management
- Delivery Proof Upload
- Real-time Notifications
- ESP32-CAM Live Camera
- ESP32-CAM Image Capture
- AI Lettuce Disease Detection
- Healthy Lettuce Detection
- Diagnostic Results
- Diagnostic History
- Weather Monitoring
- Crop Monitoring
- QR Scanner
- Farmer Profile
- Supabase Realtime Integration

## Technologies

- Flutter
- Dart
- Supabase
- HTTP
- Image Picker
- Geolocator
- Flutter Animate
- Shared Application Services

---

# 🌐 Buyer Website

The buyer website is developed using **Next.js**.

It allows customers to browse available lettuce products and purchase directly from registered farmers.

## Features

- Buyer Authentication
- Product Catalog
- Product Search
- Product Details
- Shopping Cart
- Checkout
- Delivery Option
- Pickup Option
- Cash on Delivery
- GCash
- Bank Transfer
- Order History
- Order Tracking
- Notifications
- Buyer Profile
- Order Confirmation

## Technologies

- Next.js
- React
- TypeScript
- Tailwind CSS
- Supabase

---

# 🖥 Admin Dashboard

The Admin Dashboard is designed for monitoring and managing the overall GreenGuard AI ecosystem.

## Features

- User Monitoring
- Farmer Monitoring
- Buyer Monitoring
- Product Monitoring
- Order Monitoring
- Order Status Viewer
- Delivery Proof Viewer
- Diagnostic Log Monitoring
- Dashboard Statistics
- Reports
- Analytics

The Admin Dashboard shares the same backend data stored in Supabase.

---

# 🤖 AI Lettuce Disease Detection

GreenGuard AI uses a custom-trained **YOLOv8s object detection model** for identifying healthy lettuce and detecting selected lettuce diseases.

The system currently supports four final AI classes.

## Final AI Classes

```text
0 - Healthy
1 - Downy Mildew
2 - Powdery Mildew
3 - Septoria Blight
```

## Disease Mapping

### Healthy

Healthy lettuce with no visible signs of the supported diseases.

### Downy Mildew

Scientific organism:

```text
Bremia lactucae
```

### Powdery Mildew

Scientific organism:

```text
Erysiphe cichoracearum
```

### Septoria Blight / Septoria Leaf Spot

Scientific organism:

```text
Septoria lactucae
```

---

# 🧠 AI Processing Architecture

The AI processing pipeline does more than immediately send an image into YOLO.

The current intended workflow is:

```text
Captured Image
      │
      ▼
Image Decode
      │
      ▼
Image Enhancement
      │
      ▼
Subject Identification
      │
      ├── Unknown / Non-Plant
      │
      ├── Plant
      │
      └── Lettuce
              │
              ▼
        YOLOv8 Detection
              │
              ├── Healthy
              ├── Downy Mildew
              ├── Powdery Mildew
              └── Septoria Blight
              │
              ▼
        Diagnosis Result
              │
              ▼
       Farmer Mobile App
```

Subject identification is performed before the final four-class lettuce diagnosis.

---

# ✨ Image Enhancement System

GreenGuard AI includes an image enhancement stage before disease detection.

The purpose is to improve images captured under imperfect field conditions without aggressively rejecting usable photos.

The enhancement pipeline can perform:

- Low-light correction
- Gamma adjustment
- CLAHE contrast enhancement
- Mild bilateral denoising
- Mild sharpening
- Soft-image improvement
- Contrast improvement

Valid decoded images are processed and passed forward to the AI model.

Only corrupted or unreadable images should fail processing.

---

# 🧠 GreenGuard AI Dataset

The GreenGuard AI dataset was rebuilt into a clean final four-class dataset.

Several public lettuce datasets were merged and remapped into the GreenGuard AI class structure.

Unrelated source classes were removed.

## Excluded Source Classes

- Bacterial
- Lettuce Mosaic Virus
- Viral

The final dataset uses standard **YOLO object detection bounding-box annotations**.

Polygon annotations found in source datasets were converted into YOLO bounding boxes to maintain one consistent detection format.

---

# 📊 Final Dataset Distribution

## Training Dataset

```text
Total Training Images: 6,571

Healthy
971 images
2,382 annotations

Downy Mildew
1,990 images
2,388 annotations

Powdery Mildew
1,544 images
2,198 annotations

Septoria Blight
2,112 images
2,482 annotations
```

## Validation Dataset

```text
Total Validation Images: 737

Healthy
251 images
467 annotations

Downy Mildew
180 images
204 annotations

Powdery Mildew
143 images
200 annotations

Septoria Blight
167 images
201 annotations
```

## Test Dataset

```text
Total Test Images: 513

Healthy
141 images
313 annotations

Downy Mildew
119 images
137 annotations

Powdery Mildew
103 images
143 annotations

Septoria Blight
151 images
172 annotations
```

## Dataset Verification

```text
TRAIN
Images: 6571
Labels: 6571
Status: OK

VALIDATION
Images: 737
Labels: 737
Status: OK

TEST
Images: 513
Labels: 513
Status: OK
```

Final label verification:

```text
TRAIN Invalid Labels: 0
VAL Invalid Labels: 0
TEST Invalid Labels: 0
```

All final annotations are clean YOLO detection bounding boxes.

---

# 🏋️ YOLOv8 Training

GreenGuard AI currently uses **YOLOv8s** as the main lettuce disease detection model.

## Current Training Configuration

```text
Model:
YOLOv8s

Input Resolution:
640 × 640

Training Images:
6,571

Validation Images:
737

Test Images:
513

Maximum Epochs:
100

Early Stopping:
20 Epoch Patience

Dataset Fraction:
100%

Pretrained Weights:
Enabled

GPU:
NVIDIA GeForce GTX 1660 SUPER

CUDA:
Enabled
```

Unlike earlier experimental training, the current final training process uses the **entire dataset**.

```text
fraction = 1.0
```

The previous experimental configuration that used only 10% of the dataset is no longer used for the final model.

---

# 📈 Current AI Training Progress

Final YOLOv8 training is currently in progress.

Recent validation results during training have shown continued improvement.

Example intermediate results:

```text
Epoch 3
mAP50: 0.485
mAP50-95: 0.300

Epoch 4
mAP50: 0.530
mAP50-95: 0.334

Epoch 5
mAP50: 0.596
mAP50-95: 0.362

Epoch 6
mAP50: 0.641
mAP50-95: 0.418

Epoch 7
mAP50: 0.676
mAP50-95: 0.434

Epoch 8
mAP50: 0.717
mAP50-95: 0.481

Epoch 9
mAP50: 0.770
mAP50-95: 0.521

Epoch 10
mAP50: 0.757
mAP50-95: 0.529
```

These results are **validation results during training** and are not the final claimed system accuracy.

The final model will be evaluated using the untouched test dataset and real ESP32-CAM images before final performance is reported.

---

# 💾 AI Training Checkpoints

YOLO automatically saves model checkpoints during training.

The main files are:

```text
best.pt
last.pt
```

`best.pt` represents the best-performing model checkpoint based on validation performance.

`last.pt` represents the latest completed training epoch and is used when training needs to be resumed.

Training can therefore be safely stopped and resumed later.

---

# 📷 ESP32-CAM Integration

GreenGuard AI currently uses an:

```text
AI Thinker ESP32-CAM
OV2640 Camera
```

The ESP32-CAM is responsible for capturing lettuce images that can be processed by the AI server.

## ESP32-CAM Workflow

```text
ESP32-CAM
      │
      ▼
Live Camera Stream
      │
      ▼
Farmer Captures Image
      │
      ▼
Captured JPEG Image
      │
      ▼
GreenGuard AI Server
      │
      ▼
Image Enhancement
      │
      ▼
Subject Identification
      │
      ▼
YOLOv8 Detection
      │
      ▼
Diagnosis
      │
      ▼
Flutter Farmer App
```

---

# 💡 ESP32-CAM Flash System

The ESP32-CAM onboard flash can be used for additional crop illumination.

The system is designed so that the captured image should maintain the same camera configuration used during the live stream.

This helps prevent major differences between what the farmer sees before capturing and the actual image sent to the AI model.

---

# 🌱 Ground IoT Monitoring

GreenGuard AI also includes a separate ground-based IoT monitoring concept.

A dedicated ESP32 can be installed in the crop area and connected to environmental sensors.

The ground IoT device operates independently from the drone.

## Planned Architecture

```text
Soil Sensor
     │
     ▼
Ground ESP32
     │
     ▼
Wi-Fi
     │
     ▼
GreenGuard Platform
     │
     ▼
Farmer Mobile App
```

## Current Planned Sensor

- Soil Moisture Sensor

Additional environmental monitoring may be added depending on approved capstone scope.

---

# 🌦 Weather Integration

GreenGuard AI integrates weather information using:

```text
OpenWeatherMap
```

Weather information can be displayed inside the farmer application to provide additional crop-monitoring context.

Weather data may also be associated with diagnostic information for future crop analysis.

---

# 🚁 GreenGuard Smart Farming Drone

GreenGuard AI is also being developed toward drone-assisted and eventually autonomous lettuce monitoring.

The drone is intended to carry the ESP32-CAM and capture images of lettuce crops from above.

## Current Drone Concept

```text
GreenGuard Flutter App
        │
        ▼
     Wi-Fi
        │
        ▼
    ESP32-CAM
        │
        ▼
   Flight System
        │
        ▼
 Lettuce Area
        │
        ▼
 Image Capture
        │
        ▼
 AI Disease Analysis
```

---

# 🛰 Planned Autonomous Drone Navigation

The long-term GreenGuard drone goal is to reduce the need for farmers to manually control the drone during normal crop-monitoring missions.

The planned autonomous architecture includes:

```text
GreenGuard App
      │
      ▼
Mission / Scan Request
      │
      ▼
ESP32-CAM / Communication
      │
      ▼
F405 Flight Controller
      │
      ├── GPS
      ├── Compass
      └── INAV
      │
      ▼
Autonomous Navigation
```

## Planned Mission Workflow

```text
Farmer Starts Mission
        │
        ▼
Drone Takeoff
        │
        ▼
Navigate to Lettuce Plot
        │
        ▼
Waypoint A1
        │
        ▼
Capture Image
        │
        ▼
Waypoint A2
        │
        ▼
Capture Image
        │
        ▼
Waypoint A3
        │
        ▼
Capture Image
        │
        ▼
Return Home
        │
        ▼
Land
```

The RC transmitter/controller remains useful for:

- Setup
- Calibration
- Testing
- Manual override
- Emergency control

Normal future operation is intended to become increasingly automated.

---

# 🗺 GPS and Mapping

Google Maps or another mapping interface can be used in the GreenGuard application for:

- Displaying farm areas
- Selecting crop locations
- Visualizing plots
- Displaying drone locations
- Planning scan locations

However, map APIs do not replace onboard drone positioning.

The drone still requires its own navigation hardware such as:

- GPS
- Compass

for real-time autonomous flight.

---

# 🔔 Notification System

GreenGuard AI contains a real-time notification system connecting buyers and farmers.

Notifications can be generated from order events and delivery events.

## Example Notifications

- New Order
- Delivery Update
- Preparing Order
- Shipped Order
- Delivered Order
- Delivery Proof Uploaded
- Buyer Confirmed Received

## Notification Architecture

```text
USER
  │
  ▼
receives
  │
  ▼
NOTIFICATION
  ▲
  │
generated from
  │
ORDER
  │
  ▼
ORDER ITEMS
  │
  ▼
PRODUCTS
```

---

# 🛒 E-commerce Order Workflow

```text
Buyer
  │
  ▼
Browse Lettuce Products
  │
  ▼
Add to Cart
  │
  ▼
Checkout
  │
  ▼
Choose Delivery / Pickup
  │
  ▼
Choose Payment Method
  │
  ├── Cash on Delivery
  ├── GCash
  └── Bank Transfer
  │
  ▼
Order Stored in Supabase
  │
  ▼
Farmer Notification
  │
  ▼
Farmer Accepts Order
  │
  ▼
Preparing
  │
  ▼
Shipped / Ready for Pickup
  │
  ▼
Delivery Proof
  │
  ▼
Buyer Confirms Received
  │
  ▼
Completed
```

---

# 🗄 Backend

GreenGuard AI uses **Supabase** as its main cloud backend.

## Supabase Services

- Authentication
- PostgreSQL Database
- Storage
- Row Level Security
- Realtime
- Image Upload
- File Upload
- User Roles
- Order Data
- Diagnostic Data

---

# 🗃 Core Database Entities

Important GreenGuard AI database entities include:

```text
USERS
PRODUCTS
ORDERS
ORDER_ITEMS
NOTIFICATIONS
DIAGNOSTIC_LOGS
```

## Diagnostic Logs

Diagnostic logs are intended to store information such as:

- Detected disease
- Confidence score
- Captured image
- Capture timestamp
- Weather information
- Environmental context
- Device information

This allows farmers to review previous crop diagnoses inside the mobile application.

---

# 🩺 Diagnostic History

The farmer application includes a diagnostic monitoring interface.

The system can display information such as:

```text
Total Scans
Healthy Results
Risk / Disease Results
Disease Name
Confidence
Date
Weather
Temperature
Image
```

The final AI model will be connected directly to this diagnostic workflow after model evaluation is completed.

---

# 📂 Current Repository Structure

The current GitHub repository contains the Flutter application, buyer web application, AI server code, training scripts, and related project assets.

```text
letus-plant/

├── android/
│   └── Android application configuration
│
├── assets/
│   ├── images/
│   └── icon/
│
├── lib/
│   ├── screens/
│   ├── services/
│   ├── widgets/
│   └── main.dart
│
├── letus-plant-buyer-web/
│   └── Next.js Buyer Website
│
├── GreenGuard_AI_Model/
│   ├── create_subset.py
│   ├── image_enhancer.py
│   ├── server.py
│   └── train.py
│
├── pubspec.yaml
├── pubspec.lock
└── README.md
```

Large AI datasets and training runs are stored locally and are not normally committed to GitHub.

---

# 📁 Local AI Development Structure

The full local AI training environment contains:

```text
C:\Capstone\GreenGuard_AI_Model\

├── raw_dataset/
│
├── healthy_dataset/
│
├── healthy_dataset_2/
│
├── dataset/
│
├── dataset_backup_*/
│
├── runs/
│   └── detect/
│       └── greenguard_final/
│           └── weights/
│               ├── best.pt
│               └── last.pt
│
├── create_subset.py
├── image_enhancer.py
├── server.py
├── train.py
└── yolov8s.pt
```

Datasets and training outputs are intentionally kept out of normal Git tracking because of their size.

---

# 🛠 Technologies Used

## Mobile Development

- Flutter
- Dart

## Web Development

- Next.js
- React
- TypeScript
- Tailwind CSS

## Backend

- Supabase
- PostgreSQL
- Supabase Authentication
- Supabase Storage
- Supabase Realtime
- Row Level Security

## Artificial Intelligence

- Python
- Ultralytics
- YOLOv8
- PyTorch
- OpenCV
- Computer Vision

## IoT

- ESP32
- ESP32-CAM
- OV2640 Camera
- Wi-Fi Communication

## Weather

- OpenWeatherMap API

## Drone Development

Planned / developing technologies include:

- F405 Flight Controller
- GPS
- Compass
- INAV
- ESP32-CAM
- RC Emergency Control

---

# 🔐 Security

GreenGuard AI uses several security mechanisms.

These include:

- Supabase Authentication
- Role-based access
- Row Level Security
- Protected database operations
- Secure storage access
- Environment variables for sensitive configuration

Sensitive information such as passwords, Wi-Fi credentials, service keys, and private API secrets should never be committed to the public GitHub repository.

---

# 📌 Current Project Status

## ✅ Completed / Working

- Flutter Farmer Application Foundation
- Buyer Website
- Supabase Authentication
- Role-based Authentication
- Farmer Dashboard
- Buyer Dashboard
- Product Management
- Product Image Upload
- Shopping Cart
- Checkout
- Delivery / Pickup Options
- Order Management
- Order Status Updates
- Notifications
- Delivery Proof Upload
- Supabase Database Integration
- Supabase Storage Integration
- ESP32-CAM Connection
- ESP32-CAM Live Stream
- ESP32-CAM Image Capture
- ESP32-CAM Flash Control
- AI Server
- Image Enhancement System
- Subject Identification Pipeline
- Healthy Lettuce Dataset Integration
- Disease Dataset Integration
- Dataset Class Remapping
- Removal of Unsupported Disease Classes
- Polygon-to-Bounding-Box Conversion
- Clean Four-Class Detection Dataset
- Train / Validation / Test Dataset Separation
- YOLOv8 Final Training Pipeline
- Training Checkpoint Resume Support

---

# 🚧 Currently In Progress

- Final YOLOv8 Training
- Final Model Evaluation
- Test Dataset Evaluation
- Confusion Matrix Review
- Precision / Recall Evaluation
- mAP50 Evaluation
- mAP50-95 Evaluation
- Real ESP32-CAM Lettuce Testing
- Final `best.pt` Integration
- Flutter AI Result Integration
- Diagnostic Log Saving
- Real Environmental Monitoring
- Soil Moisture Integration
- Autonomous Drone Navigation
- GPS Integration
- Compass Integration
- Production Deployment

---

# 🎯 Current Development Priority

The current GreenGuard AI priority is:

```text
Finish YOLOv8 Training
        │
        ▼
Select best.pt
        │
        ▼
Evaluate on 513 Test Images
        │
        ▼
Check Precision / Recall / mAP
        │
        ▼
Review Confusion Matrix
        │
        ▼
Test Real ESP32-CAM Lettuce Images
        │
        ▼
Connect Final AI Model to server.py
        │
        ▼
Connect Results to Flutter
        │
        ▼
Save Diagnostic Logs
        │
        ▼
Complete Ground IoT Monitoring
        │
        ▼
Continue Autonomous Drone Integration
```

---

# 🧪 Final AI Evaluation Plan

Training performance alone will not be used as the final accuracy claim.

The final GreenGuard model will be evaluated using:

- Validation metrics
- Untouched 513-image test dataset
- Precision
- Recall
- mAP50
- mAP50-95
- Confusion Matrix
- Per-class performance
- Real ESP32-CAM images
- Different lighting conditions
- Real lettuce plants

The project may target very high accuracy, but final accuracy will only be reported after proper evaluation.

---

# 🌾 Intended Farmer Workflow

The final GreenGuard AI farmer workflow is intended to become:

```text
Farmer Opens GreenGuard
        │
        ▼
Checks Dashboard
        │
        ├── Orders
        ├── Weather
        ├── Monitoring
        └── Crop Health
        │
        ▼
Starts Lettuce Scan
        │
        ▼
ESP32-CAM Captures Crop
        │
        ▼
AI Analyzes Image
        │
        ▼
GreenGuard Displays Result
        │
        ├── Healthy
        ├── Downy Mildew
        ├── Powdery Mildew
        └── Septoria Blight
        │
        ▼
Diagnostic Result Saved
        │
        ▼
Farmer Reviews Crop History
```

Future automated drone monitoring will extend this workflow by allowing multiple crop areas to be scanned automatically.

---

# 🌍 Project Goal

GreenGuard AI aims to provide lettuce farmers with one integrated digital platform for:

- Crop health monitoring
- Early disease detection
- IoT monitoring
- Environmental awareness
- Product selling
- Order management
- Buyer communication
- Diagnostic history
- Smart farming automation

Instead of requiring separate tools for farming, AI diagnosis, selling, monitoring, and crop inspection, GreenGuard AI brings these functions together into a single ecosystem.

---

# 👨‍💻 Developed By

**Emelio Mondares**

Bachelor of Science in Information Technology

University of Cebu Lapu-Lapu and Mandaue

---

# 🎓 Capstone Project

GreenGuard AI was developed as an undergraduate Information Technology capstone project.

The system focuses on the application of:

- Artificial Intelligence
- Computer Vision
- Internet of Things
- Mobile Development
- Web Development
- Cloud Backend Services
- Smart Agriculture
- E-commerce
- Drone-assisted Crop Monitoring

---

# 📜 License

This project was developed primarily for:

- Educational purposes
- Academic research
- Capstone demonstration
- Portfolio purposes

Third-party datasets, libraries, APIs, frameworks, and tools remain subject to their respective licenses.
