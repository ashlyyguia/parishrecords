# 📘 Parish Operational Management System with ML Kit OCR

## 🏛 Overview

The **Parish Operational Management System with ML Kit OCR** is a web-based system designed to digitize and manage parish operations. It replaces manual record-keeping with a modern system that uses **OCR (Optical Character Recognition)** to scan and extract sacramental records.

The system integrates **Firebase services** for real-time data handling and authentication, a **Railway-hosted Node.js backend API** for server-side processing and OCR orchestration, and a **Python CV grid service** (self-hosted on a VPS) that detects the ruled grid of register spreads before text OCR.

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
- **Manage users** – Create, edit, delete user accounts with role assignment
- Manage households, reports, and settings
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

### 👤 User Management (Admin Only)
- **Create new users** with email, password, display name, and role
- Assign roles: Admin, Staff, Finance, Parishioner
- Edit user roles and permissions
- Disable/enable user accounts
- Delete user accounts with confirmation
- View user registration dates and last login
- Search and filter users by role, name, or email

### 📋 Records Management
- Modern datatable interface with full-page layout
- View, edit, and delete sacramental records
- Actions dropdown menu for compact organization
- Support for Baptism, Marriage, Confirmation, and Funeral records
- Record type badges with color coding
- Parish location filtering
- Date-based record filtering and sorting

---

## 🧱 System Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                   Flutter (Web / Desktop)                     │
│   Talks to Firebase directly, and to the backend API via     │
│   BACKEND_URL (compile-time dart-define).                    │
└───────────────┬───────────────────────────────┬──────────────┘
                │                               │
                ↓                               ↓
┌───────────────────────────────┐   ┌──────────────────────────────┐
│        Firebase Services       │   │   Node.js / Express backend  │
│  • Authentication              │   │  Local:  http://localhost:3000│
│  • Firestore DB                │   │  Prod:   Railway service      │
│  • Cloud Messaging (FCM)       │   │  (business logic, OCR orch.)  │
└───────────────────────────────┘   └───────────────┬──────────────┘
                                                     │
                          ┌──────────────────────────┴───────────────┐
                          ↓                                          ↓
        ┌────────────────────────────────────┐   ┌──────────────────────────────┐
        │   CV Grid Service (Python/FastAPI) │   │      OCR.space (cloud)       │
        │   Local:  http://127.0.0.1:8000    │   │  Handwriting text OCR on the │
        │   Prod:   VPS 187.53.141.101:8000  │   │  rectified page images.      │
        │   Finds the ruled grid, rectifies  │   │  (OCRSPACE_API_KEY)          │
        │   the two pages. No text OCR here. │   └──────────────────────────────┘
        └────────────────────────────────────┘
```

> The register-scanning path is a three-hop chain: **Flutter → backend → CV grid
> service**, with the backend also calling **OCR.space** for the actual
> handwriting recognition. The CV service does grid detection and page
> rectification only; there is no local text-OCR engine. See
> [Running the App](#-running-the-app--local--production) below for how each hop
> is pointed at local vs production.

---

## 🛠 Technology Stack

### Frontend
- **Flutter** (Web / Mobile / Desktop)
- **Dart** programming language
- **Riverpod** for state management
- **Go Router** for navigation

### Backend (Live API)
- **Node.js** + **Express**
- Hosted on **Railway** (production); runs locally on port `3000`
- **Firebase Admin SDK** for server-side operations
- Orchestrates OCR: calls the CV grid service, then OCR.space

### Cloud Services (Firebase)
- **Firebase Authentication** – User authentication & role management
- **Firebase Firestore** – NoSQL document database
- **Firebase Storage** – Image & document storage
- **Firebase Cloud Messaging** – Push notifications

### OCR / Register scanning
- **CV Grid Service** (`ocr_service/`) – Python + FastAPI + OpenCV; finds the
  register's ruled grid and rectifies the two pages (no text recognition)
- **OCR.space** – cloud handwriting text OCR run by the backend on the
  rectified page images

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

## 🚀 Running the App — Local & Production

The register-scanning feature spans three hops (Flutter → backend → CV grid
service, plus the backend's OCR.space calls). "Running locally" vs "production"
is just a matter of pointing each hop at the right host. This table is the whole
story; the steps below apply it.

| Hop / setting | Where | Local | Production |
|---|---|---|---|
| Flutter → backend base URL | `BACKEND_URL` dart-define | `http://localhost:3000` (built-in default) | Railway URL, from `dart_define.json` |
| Backend HTTP port | `PORT` in `backend/.env` | `3000` | assigned by Railway |
| Backend → CV grid service | `OCR_SERVICE_URL` in `backend/.env` | `http://127.0.0.1:8000` | `http://187.53.141.101:8000` (VPS) |
| Backend ↔ CV shared secret | `OCR_SERVICE_KEY` (both sides) | `dev-key` | long random string, identical on both |
| Handwriting text OCR | `OCRSPACE_API_KEY` in `backend/.env` | your ocr.space key | same (this hop is **always** cloud) |
| Allowed browser origins | `ALLOWED_ORIGINS` in `backend/.env` | `http://localhost:3000,http://127.0.0.1:3000` | your deployed web origin |

> **"Pure local" caveat:** the local CV service only does grid detection and page
> rectification. The actual handwriting recognition always calls **OCR.space**
> (a cloud API keyed by `OCRSPACE_API_KEY`) — there is no offline text-OCR engine
> in this stack. Running locally gets you off Railway and the VPS, not off the
> internet entirely.

### ▶️ Run everything locally

Use three terminals (the CV service must stay up while you scan).

**1. CV grid service** — `ocr_service/` (FastAPI, port 8000):

```bash
cd ocr_service
# First time only: create the venv and install deps
python -m venv .venv310
.venv310/Scripts/python -m pip install -r requirements.txt   # Windows
# .venv310/bin/pip install -r requirements.txt               # macOS/Linux

# Start it (key must match backend/.env → OCR_SERVICE_KEY)
OCR_SERVICE_KEY=dev-key .venv310/Scripts/python -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

See `ocr_service/README.md` for the helper scripts (`scripts/start-ocr-service.sh` / `.bat`).

**2. Backend** — `backend/` (Express, port 3000):

```bash
cd backend
npm install                     # first time only
cp .env.example .env            # first time; then fill in the values below
npm run dev
```

Set these in `backend/.env` for local:

```env
PORT=3000
ALLOWED_ORIGINS=http://localhost:3000,http://127.0.0.1:3000
OCR_SERVICE_URL=http://127.0.0.1:8000      # point at the LOCAL CV service
OCR_SERVICE_KEY=dev-key                    # must equal the CV service's key
OCR_TIMEOUT_MS=120000
OCRSPACE_API_KEY=your_ocrspace_key
FIREBASE_SERVICE_ACCOUNT_JSON={"type":"service_account",...}
```

> If `backend/.env` already contains a production `OCR_SERVICE_URL` line (the VPS
> address), make sure the **local** value is the one that takes effect — dotenv
> keeps the *last* definition of a duplicated key, so remove or comment the VPS
> line when running locally.

**3. Flutter** — from the repo root, pointed at the local backend:

```bash
flutter pub get                 # first time only
flutter run                     # uses the built-in default http://localhost:3000
```

Do **not** pass `--dart-define-from-file=dart_define.json` for local runs — that
file points at the production Railway URL. To be explicit you can instead pass
`--dart-define=BACKEND_URL=http://localhost:3000`.

> **Flutter web + CORS:** the web dev server picks a random port that won't be in
> `ALLOWED_ORIGINS`, so the backend will reject it. Either run a desktop build
> (`flutter run -d windows`), or pin the port and whitelist it:
> `flutter run -d chrome --web-port 5000` and add `http://localhost:5000` to
> `ALLOWED_ORIGINS`. (Requests from localhost also bypass auth via
> `DEV_BYPASS_AUTH`/localhost detection, which is convenient for local testing.)

### ☁️ Run against production

Each hop lives on its own host; nothing runs on your machine except the Flutter
build you're testing.

**Backend — Railway** (deploys from the `development` branch):
- Root directory: `backend/`
- Start command: `node src/server.js` (see `backend/railway.json` / `Procfile`)
- Health check: `/health`
- `PORT` is injected by Railway — do not hardcode it.
- Set the production env vars in the Railway dashboard: `OCR_SERVICE_URL=http://187.53.141.101:8000`, a strong `OCR_SERVICE_KEY` (matching the VPS), `OCRSPACE_API_KEY`, `FIREBASE_SERVICE_ACCOUNT_JSON`, `ALLOWED_ORIGINS`, and the EmailJS keys.

**CV grid service — VPS** (`187.53.141.101`):
- Start bound to all interfaces so Railway can reach it:
  `uvicorn app.main:app --host 0.0.0.0 --port 8000`
- Set `OCR_SERVICE_KEY` to the same strong secret configured on Railway.

**Flutter — production build** (pointed at Railway via `dart_define.json`):

```bash
flutter build web --dart-define-from-file=dart_define.json
firebase deploy --only hosting
```

`dart_define.json` holds the production backend URL:

```json
{ "BACKEND_URL": "https://parishrecords-production.up.railway.app" }
```

---

## 🔌 API Endpoints

#### User Management
- **POST** `/api/admin/users` – Create new user (Admin only)
  ```json
  {
    "email": "user@example.com",
    "displayName": "John Doe",
    "password": "password123",
    "role": "staff"
  }
  ```
  Response: `{ success: true, user: { id, email, displayName, role } }`

- **GET** `/api/admin/users` – List all users (Admin only)
- **DELETE** `/api/admin/users/:id` – Delete user (Admin only)
- **PATCH** `/api/admin/users/:id/role` – Update user role (Admin only)

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

### Admin User Creation Flow
1. **Admin navigates** to User Management page
2. **Clicks "New User"** button to open creation modal
3. **Fills form** with email, display name, password, and role
4. **Frontend validates** input (email format, password length)
5. **Request sent** to backend with Firebase ID token
6. **Backend verifies** admin role via `requireAdmin` middleware
7. **Firebase Auth user created** with Admin SDK
8. **Custom claims set** for role-based access
9. **Firestore user document created** with profile info
10. **User can now log in** with assigned credentials

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

## 📋 Recent Updates (v1.1.0)

### New Features
- ✨ **Admin User Management** – Create, edit, and manage system users
  - Secure user creation via backend API (`POST /api/admin/users`)
  - Role assignment (Admin, Staff, Finance, Parishioner)
  - Password validation and Firebase Auth integration
  - User deletion and role modification

### UI/UX Improvements
- 🎨 **Modernized Datatables** – Full-page responsive layout for records and users
- 🔘 **Unified Button Style** – Consistent `FilledButton.icon` styling across admin pages
- 📌 **Actions Menu** – Consolidated record/user actions into dropdown menus
- 🎯 **Better Layout** – Improved spacing, typography, and visual hierarchy
- ✅ **Form Validation** – Real-time validation for user creation forms

### Backend Enhancements
- 🔒 **Admin-only Endpoint** – `requireAdmin` middleware on user creation
- 🔑 **Custom Claims** – Proper role assignment via Firebase Admin SDK
- ✔️ **Input Validation** – Email, password, and role validation

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

## 🎨 UI/UX Improvements

### Admin Dashboard Enhancements
- **Unified button styling** using `FilledButton.icon` for consistency
- **Modern datatables** with full-page responsive layout
- **Rounded corners and borders** for polished design
- **Actions dropdown menus** to consolidate multiple actions
- **Color-coded badges** for role and status indicators
- **Improved spacing and typography** for better readability

### User Management Interface
- Clean modal dialog for creating users
- Real-time form validation
- Loading indicator during user creation
- Success/error notifications with visual feedback
- Password strength indicator (minimum 6 characters)

### Records Management Interface
- Professional datatable with horizontal scrolling
- Compact actions menu with View, Edit, Certificate, Delete options
- Record type color coding (Baptism, Marriage, Confirmation, Funeral)
- Full-page layout matching user management style
- Responsive design for various screen sizes

---

## 🛠 Development Setup

### Prerequisites
- Flutter SDK (3.9.2 or later)
- Node.js (LTS version)
- Firebase CLI
- Android Studio / Xcode (for mobile)

### Quick Start

```bash
# 1. Clone + install
git clone <repo-url>
cd parishrecord
flutter pub get
cd backend && npm install && cp .env.example .env && cd ..
# Edit backend/.env (see the table in "Running the App" above)

# 2. Terminal A — CV grid service (required for scanning)
cd ocr_service
python -m venv .venv310 && .venv310/Scripts/python -m pip install -r requirements.txt
OCR_SERVICE_KEY=dev-key .venv310/Scripts/python -m uvicorn app.main:app --host 127.0.0.1 --port 8000

# 3. Terminal B — backend
cd backend && npm run dev            # http://localhost:3000

# 4. Terminal C — Flutter (defaults to http://localhost:3000)
flutter run                          # add -d windows, or -d chrome --web-port 5000 (see CORS note)
```

For the full local-vs-production breakdown of every setting, see
[Running the App — Local & Production](#-running-the-app--local--production) above.

---

## 📝 License

This project is developed for **capstone research purposes** as part of IT Elective coursework.

---

## 👥 Team

Developed by **[Your Team Name]** – *Capstone Project 2024*

---

*For questions or support, contact the development team.*
