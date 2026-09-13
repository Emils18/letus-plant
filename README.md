# 🌱 GreenGuard AI

### AI + IoT Smart Farming Platform for Lettuce Disease Detection, Monitoring, and E-commerce

GreenGuard AI is an undergraduate capstone project that combines **Artificial Intelligence, IoT, Mobile Development, Web Technologies, and Smart Farming** into one integrated platform.

The system helps lettuce farmers monitor crops, detect diseases using AI, manage products and orders, receive notifications, monitor environmental information, and sell directly to buyers.

---

# 🚀 Project Overview

GreenGuard AI consists of multiple connected components using **Supabase** as the primary backend.

```text
                    GreenGuard AI Ecosystem

                 ┌───────────────────────┐
                 │     Buyer Website     │
                 │       Next.js         │
                 └───────────┬───────────┘
                             │
                         Orders
                             │
                             ▼
                    ┌─────────────────┐
                    │    Supabase     │
                    │ Auth / Database │
                    │ Storage / RLS   │
                    │    Realtime     │
                    └────────┬────────┘
                             │
              ┌──────────────┴──────────────┐
              │                             │
              ▼                             ▼

      Farmer Mobile App              Admin Dashboard
          Flutter                       Next.js

              │
              ▼

         ESP32-CAM
              │
        Capture Image
              │
              ▼
      GreenGuard AI Server
              │
              ▼
         YOLOv8 Model
              │
              ▼
      Disease Diagnosis
              │
              ▼
      Farmer Mobile App
