# 📘 Parish Operational Management System with ML Kit OCR

## 🏛 Overview

The **Parish Operational Management System with ML Kit OCR** is a web-based system designed to digitize and manage parish operations. It replaces manual record-keeping with a modern system that uses **OCR (Optical Character Recognition)** to scan and extract sacramental records.

The system integrates **Firebase services** for real-time data handling and authentication, while a **Render-hosted backend API** manages server-side processing and business logic.

---

## 🎯 Objectives

- **Digitize sacramental records** – Convert physical parish records into digital format
- **Automate certificate requests** – Enable online certificate requests with status tracking
- **Improve efficiency of parish operations** – Streamline administrative tasks and reduce paperwork
- **Reduce manual errors using OCR** – Automate data extraction from scanned documents
- **Provide online services for parishioners** – Allow parishioners to access services remotely

---

## 👥 User Roles

### 👑 Admin
- Full system access
- Manage users, households, reports, and settings
- System configuration and audit log monitoring
- Analytics dashboard access

### 🧑‍💼 Parish Staff
- Manage households and parishioners
- Scan records using OCR
- Process certificate requests
- Handle sacramental record entry

### 💳 Finance Staff
- Monitor donations
- Generate financial reports
- Reconcile donation records
- Access donation ledger

### 🙋 Parishioner
- Request certificates
- View records and donation history
- Manage household information
- Schedule appointments

---

## ⚙️ Key Features

### 🏠 Household Management
- Manage family records
- Add/edit members
- Link sacramental data to family members
- Household member tracking

### 🤖 OCR Integration (ML Kit)
- Scan sacrament records using Google ML Kit
- Extract text automatically from scanned documents
- Verify and store extracted data
- Reduce manual data entry errors

### 🧾 Certificate Requests
- Online certificate submission
- Real-time status tracking
- Certificate generation and printing (PDF)
- Request history tracking

### 💳 Donation System
- GCash / Bank / Card support
- Donation tracking
- Receipt generation
- Financial reporting

### 📅 Events & Announcements
- Publish parish events
- Manage announcements
- Public landing page for community updates

### 📊 Reports & Analytics
- Generate reports (PDF / Excel)
- Dashboard statistics
- Audit logs for compliance
- Performance analytics

---

## 🧱 System Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Flutter Web / App                     │
│         (Cross-platform frontend application)           │
└────────────────────┬────────────────────────────────────┘
                     │
                     ↓
┌─────────────────────────────────────────────────────────┐
│                  Firebase Services                       │
│  • Authentication  • Firestore DB  • Storage  • FCM   │
└────────────────────┬────────────────────────────────────┘
                     │
                     ↓
┌─────────────────────────────────────────────────────────┐
│              Render Backend API (Node.js)                │
│           Business logic & server-side processing       │
└────────────────────┬────────────────────────────────────┘
                     │
                     ↓
┌─────────────────────────────────────────────────────────┐
│              External Services Integration               │
│         Google ML Kit OCR  •  Email Services           │
└─────────────────────────────────────────────────────────┘
```

---

## 🛠 Technology Stack

### Frontend
- **Flutter** (Web / Mobile / Desktop)
- **Dart** programming language
- **Riverpod** for state management
- **Go Router** for navigation

### Backend (Live API)
- **Node.js** + **Express**
- Hosted on **Render**
- **Firebase Admin SDK** for server-side operations

### Cloud Services (Firebase)
- **Firebase Authentication** – User authentication & role management
- **Firebase Firestore** – NoSQL document database
- **Firebase Storage** – Image & document storage
- **Firebase Cloud Messaging** – Push notifications

### OCR
- **Google ML Kit OCR** – On-device text recognition
- **Google ML Kit Text Recognition** – Document scanning

### Payment Integration (Future)
- **GCash** / **PayMongo** / **PayPal**

---

## 🔥 Firebase Setup

### 1. Create Firebase Project
- Go to [Firebase Console](https://console.firebase.google.com)
- Create a new project
- Enable the following services:

### 2. Enable Services
- **Authentication** (Email/Password provider)
- **Firestore Database** (Create database in production mode)
- **Storage** (For images and OCR uploads)
- **Cloud Messaging** (For notifications)

### 3. Add Firebase Config to Flutter

Add your Firebase configuration to `lib/firebase_options.dart`:

```dart
await Firebase.initializeApp(
  options: const FirebaseOptions(
    apiKey: "YOUR_API_KEY",
    appId: "YOUR_APP_ID",
    messagingSenderId: "YOUR_SENDER_ID",
    projectId: "YOUR_PROJECT_ID",
    authDomain: "YOUR_PROJECT_ID.firebaseapp.com",
    storageBucket: "YOUR_PROJECT_ID.appspot.com",
  ),
);
```

### 4. Firestore Security Rules

The system includes comprehensive security rules in `firestore.rules`:
- Role-based access control (Admin, Staff, Finance, Parishioner)
- Document-level permissions
- Secure data access patterns

---

## 🚀 Render Backend Setup

### 1. Create Backend Project (Node.js)

```bash
cd backend
npm init -y
npm install express cors dotenv firebase-admin helmet express-rate-limit
```

### 2. Environment Configuration

Create `backend/.env`:

```env
PORT=3000
FIREBASE_SERVICE_ACCOUNT_JSON={"type":"service_account",...}
EMAILJS_SERVICE_ID=your_service_id
EMAILJS_TEMPLATE_ID=your_template_id
EMAILJS_PUBLIC_KEY=your_public_key
EMAILJS_PRIVATE_KEY=your_private_key
```

### 3. Start Server Locally

```bash
npm run dev
```

Server will start at `http://localhost:3000`

### 4. Deploy to Render

1. Push code to GitHub repository
2. Create new Web Service on [Render](https://render.com)
3. Connect your GitHub repository
4. Set build command: `npm install`
5. Set start command: `npm start`
6. Add environment variables in Render dashboard

---

## 🔄 System Flow

### OCR Record Processing Flow
1. **Staff scans sacrament records** using ML Kit OCR
2. **Image is uploaded** to Firebase Storage
3. **OCR extracts text** from the scanned document
4. **Extracted data is verified** and saved in Firestore
5. **Records are linked** to household members

### Certificate Request Flow
1. **Parishioner submits certificate request** online
2. **Request is stored in Firestore** with pending status
3. **Staff processes request** through dashboard
4. **Admin approves and generates certificate** (PDF)
5. **Parishioner receives notification** when ready

### User Authentication Flow
1. **User registers** with email/password
2. **Verification code sent** via EmailJS
3. **User verifies email** and completes registration
4. **Role-based access control** determines available features
5. **JWT tokens** secure API communication

---

## 📂 Project Structure

```
parishrecord/
├── lib/                           # Flutter application
│   ├── app/                       # App bootstrap & router
│   │   ├── app.dart
│   │   ├── bootstrap.dart
│   │   └── router.dart            # GoRouter configuration
│   ├── config/                    # Configuration files
│   │   └── backend.dart           # Backend API URLs
│   ├── models/                    # Data models
│   │   ├── user.dart
│   │   ├── household.dart
│   │   ├── record.dart
│   │   ├── announcement.dart
│   │   └── notification.dart
│   ├── providers/                 # Riverpod state management
│   │   ├── auth_provider.dart
│   │   ├── records_provider.dart
│   │   └── households_provider.dart
│   ├── screens/                   # UI screens
│   │   ├── admin/                 # Admin dashboard screens
│   │   ├── staff/                 # Staff workflow screens
│   │   ├── user/                  # Parishioner screens
│   │   ├── finance/               # Finance management screens
│   │   ├── landing/               # Public landing pages
│   │   ├── login/                 # Authentication screens
│   │   ├── records/               # Record entry & viewing
│   │   └── ocr/                   # OCR processing screens
│   ├── services/                  # Business logic services
│   ├── widgets/                   # Reusable UI components
│   └── main.dart                  # Application entry point
│
├── backend/                       # Node.js API server
│   ├── src/
│   │   ├── routes/                # API route handlers
│   │   ├── middleware/            # Auth & validation middleware
│   │   ├── services/              # Business logic
│   │   ├── firebase_admin.js      # Firebase initialization
│   │   └── server.js              # Express server entry
│   ├── scripts/                   # Utility scripts
│   ├── package.json
│   └── .env                       # Environment variables
│
├── functions/                     # Firebase Cloud Functions
│   └── src/
│       ├── callables/             # Callable functions
│       └── backend/               # Background functions
│
├── web/                           # Web-specific assets
├── android/                       # Android configuration
├── ios/                           # iOS configuration
├── assets/                        # Images and icons
├── firestore.rules                # Security rules
├── firebase.json                  # Firebase configuration
└── pubspec.yaml                   # Flutter dependencies
```

---

## 🔐 Security Features

### Authentication & Authorization
- **Firebase Authentication** with email/password
- **Custom claims** for role-based access
- **JWT token validation** on API endpoints
- **Role hierarchy**: Admin > Staff > Finance > Parishioner

### Data Protection
- **Firestore Security Rules** enforce document-level permissions
- **Input validation** using express-validator
- **Rate limiting** to prevent abuse
- **Helmet.js** for HTTP security headers
- **CORS** configured for allowed origins only

### Audit & Compliance
- **Audit logs** for all administrative actions
- **Change tracking** on critical records
- **Request logging** for debugging and monitoring

---

## 📱 Platform Support

- **Web Application** – Primary platform (Flutter Web)
- **Mobile-ready** – Flutter supports iOS & Android
- **Desktop** – Windows, macOS, Linux support via Flutter
- **PWA** – Progressive Web App capabilities

---

## 🚀 Future Enhancements

### Short Term
- **Push notifications** (Firebase Cloud Messaging integration)
- **SMS alerts** for certificate readiness
- **Mobile app deployment** (iOS/Android stores)

### Long Term
- **AI handwriting improvement** for better OCR accuracy
- **Advanced analytics dashboard** with ML insights
- **Multi-parish support** for diocese-level management
- **Offline mode** with sync capabilities
- **API integrations** with church management systems

---

## 🛠 Development Setup

### Prerequisites
- Flutter SDK (3.9.2 or later)
- Node.js (LTS version)
- Firebase CLI
- Android Studio / Xcode (for mobile)

### Quick Start

```bash
# 1. Clone repository
git clone <repo-url>
cd parishrecord

# 2. Install Flutter dependencies
flutter pub get

# 3. Setup backend
cd backend
npm install

# 4. Configure environment
cp .env.example .env
# Edit .env with your Firebase credentials

# 5. Run backend
npm run dev

# 6. Run Flutter (in new terminal)
flutter run -d chrome  # For web
```

---

## 📝 License

This project is developed for **capstone research purposes** as part of IT Elective coursework.

---

## 👥 Team

Developed by **[Your Team Name]** – *Capstone Project 2024*

---

*For questions or support, contact the development team.*
