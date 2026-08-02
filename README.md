# 🌱 GreenGuard AI
### AI & IoT Smart Farming Platform for Lettuce Disease Detection and E-commerce

GreenGuard AI is a full-stack capstone project that combines **Artificial Intelligence**, **IoT**, **Mobile Development**, and **Web Technologies** into a single smart farming ecosystem.

The platform enables farmers to monitor crops, detect lettuce diseases using AI, manage products, receive customer orders in real time, and sell directly to buyers through an integrated e-commerce system.

---

# 🚀 Project Overview

GreenGuard AI consists of **three major platforms** connected through **Supabase**.

```
                   GreenGuard AI Ecosystem

                ┌─────────────────────────┐
                │     Buyer Website       │
                │      (Next.js)          │
                └──────────┬──────────────┘
                           │
                     Place Orders
                           │
                           ▼
                  ┌────────────────┐
                  │    Supabase    │
                  │ Auth Database  │
                  │ Storage RLS    │
                  └───────┬────────┘
                          │
         ┌────────────────┴───────────────┐
         │                                │
         ▼                                ▼
 Farmer Mobile App                 Admin Dashboard
    (Flutter)                         (Next.js)

         │
         ▼
  ESP32-CAM + AI Detection
         │
         ▼
 Disease Monitoring
```

---

# 📱 Mobile Application (Flutter)

Designed specifically for farmers.

### Features

- Secure Authentication
- Farmer Dashboard
- Product Management
- Order Management
- Real-time Notifications
- Delivery Proof Upload
- Disease Detection
- Weather Monitoring
- QR Scanner
- Profile Management

### Tech Stack

- Flutter
- Dart
- Supabase
- Image Picker
- Geolocator
- Flutter Animate
- HTTP

---

# 🌐 Buyer Website (Next.js)

Allows customers to purchase fresh lettuce products directly from farmers.

### Features

- User Authentication
- Product Catalog
- Product Search
- Shopping Cart
- Checkout
- Order History
- Order Tracking
- Notifications
- Buyer Profile

### Tech Stack

- Next.js
- React
- TypeScript
- Tailwind CSS
- Supabase

---

# 🖥 Admin Dashboard

Designed for administrators.

### Features

- User Management
- Product Management
- Order Monitoring
- Farmer Monitoring
- Reports
- Analytics

---

# 🤖 AI Disease Detection

GreenGuard AI uses a custom-trained **YOLOv8** model capable of identifying lettuce diseases.

Current supported diseases:

- Downy Mildew
- Powdery Mildew
- Septoria Leaf Spot

Detection results are stored inside Supabase and displayed inside the mobile application.

---

# 📷 IoT Integration

Current Hardware

- ESP32-CAM

Future Workflow

```
ESP32-CAM
      │
Capture Image
      │
      ▼
Supabase Storage
      │
      ▼
YOLO Disease Detection
      │
      ▼
Prediction Result
      │
      ▼
Farmer Mobile App
```

Future sensor support

- Temperature
- Humidity
- Soil Moisture
- Weather API

---

# 🔔 Notification System

GreenGuard AI provides a real-time notification system between buyers and farmers.

Examples

- New Order
- Order Confirmed
- Preparing
- Shipped
- Delivered
- Delivery Proof Uploaded

---

# 🛒 Order Workflow

```
Buyer

   │
   ▼

Place Order

   │
   ▼

Supabase Database

   │
   ▼

Farmer Notification

   │
   ▼

Accept Order

   │
   ▼

Preparing

   │
   ▼

Shipped

   │
   ▼

Upload Delivery Proof

   │
   ▼

Buyer Confirms Delivery

   │
   ▼

Delivered
```

---

# 🗄 Backend

Powered entirely by **Supabase**

Services used

- Authentication
- PostgreSQL Database
- Storage
- Row Level Security
- Realtime
- File Uploads

---

# 📂 Repository Structure

```
GreenGuard-AI/

├── mobile/                 # Flutter Farmer Application
│
├── buyer-web/              # Next.js Buyer Website
│
├── admin-web/              # Next.js Admin Dashboard
│
├── ai-model/               # YOLOv8 Model
│
└── documentation/
```

---

# 🛠 Technologies Used

### Mobile

- Flutter
- Dart

### Web

- Next.js
- React
- TypeScript
- Tailwind CSS

### Backend

- Supabase
- PostgreSQL

### AI

- YOLOv8

### IoT

- ESP32-CAM

---

# 📌 Current Status

### Completed

- Authentication
- Product Management
- Buyer E-commerce
- Farmer Dashboard
- Order Management
- Notifications
- Delivery Proof Upload
- Role-based Authentication
- Responsive UI
- Real-time Database Integration

### In Progress

- ESP32-CAM Live Integration
- AI Disease Prediction Integration
- Production Deployment

---

# 👨‍💻 Developed By

**Emelio Mondares**

Bachelor of Science in Information Technology

University of Cebu Lapu-Lapu and Mandaue

---

# 📜 License

This project was developed as an undergraduate capstone project.

Educational and portfolio purposes.
