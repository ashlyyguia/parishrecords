# Parish Record System - Complete Database Structure

## **Database Architecture Overview**

**Primary Database:** Firebase Firestore (NoSQL Document Database)  
**Authentication:** Firebase Authentication  
**Local Storage:** Hive (Flutter local storage)  
**File Storage:** Firebase Storage

---

## **1. AUTHENTICATION & USER MANAGEMENT**

### **Firebase Authentication**
- **Email/Password Authentication**
- **User Registration with Invite Codes**
- **Password Reset**
- **Email Verification**

### **Firestore Collection: `users`**
```javascript
users/{userId} {
  // Basic Info
  id: string,                    // Firebase Auth UID
  email: string,                 // Email address
  displayName: string,           // Full name
  phoneNumber: string,           // Contact number
  
  // Role & Permissions
  role: string,                  // "admin" | "staff" | "volunteer"
  permissions: array,            // Specific permissions array
  
  // Parish Assignment
  parishId: string,              // Assigned parish ID
  parishName: string,            // Parish name
  
  // Account Status
  isActive: boolean,             // Account active status
  isEmailVerified: boolean,      // Email verification status
  inviteCode: string,            // Invite code used for registration
  
  // Timestamps
  createdAt: timestamp,          // Account creation
  lastLogin: timestamp,          // Last login time
  updatedAt: timestamp,          // Last profile update
  
  // Metadata
  createdBy: string,             // Admin who created account
  deviceTokens: array,           // FCM tokens for notifications
}
```

### **Firestore Collection: `invites`**
```javascript
invites/{inviteId} {
  code: string,                  // Unique invite code
  email: string,                 // Invited email
  role: string,                  // Assigned role
  parishId: string,              // Parish assignment
  createdBy: string,             // Admin who created invite
  createdAt: timestamp,          // Creation time
  expiresAt: timestamp,          // Expiration time
  usedAt: timestamp,             // When invite was used
  isUsed: boolean,               // Usage status
}
```

---

## **2. PARISH RECORDS SYSTEM**

### **Firestore Collection: `parishes`**
```javascript
parishes/{parishId} {
  name: string,                  // Parish name
  address: string,               // Physical address
  contactInfo: {
    phone: string,
    email: string,
    website: string
  },
  settings: {
    timezone: string,
    language: string,
    autoBackup: boolean
  },
  createdAt: timestamp,
  updatedAt: timestamp
}
```

### **Firestore Collection: `records`**
```javascript
records/{recordId} {
  // Basic Record Info
  id: string,                    // Unique record ID
  type: string,                  // "baptism" | "marriage" | "confirmation" | "death"
  name: string,                  // Primary person name
  date: timestamp,               // Event date
  parishId: string,              // Parish ID
  
  // Certificate Status
  certificateStatus: string,     // "pending" | "approved" | "rejected"
  approvedBy: string,            // Admin who approved
  approvedAt: timestamp,         // Approval timestamp
  rejectionReason: string,       // Reason for rejection
  
  // File Attachments
  imagePath: string,             // Scanned document path
  attachments: array,            // Additional files
  
  // Detailed Information (JSON)
  notes: string,                 // JSON string with detailed form data
  
  // OCR Data
  ocrText: string,               // Extracted OCR text
  ocrConfidence: number,         // OCR confidence score
  ocrProcessedAt: timestamp,     // OCR processing time
  
  // Audit Trail
  createdBy: string,             // Staff who created
  createdAt: timestamp,          // Creation time
  updatedBy: string,             // Last updater
  updatedAt: timestamp,          // Last update
  
  // Verification
  isVerified: boolean,           // Staff verification status
  verifiedBy: string,            // Who verified
  verifiedAt: timestamp,         // Verification time
  
  // Certificate Issuance
  certificateIssued: boolean,    // Certificate issued status
  issuedBy: string,              // Who issued certificate
  issuedAt: timestamp,           // Issuance time
  certificateNumber: string,     // Certificate number
}
```

---

## **3. DETAILED FORM DATA STRUCTURES**

### **Baptism Record (stored in `notes` field as JSON)**
```javascript
{
  "registry": {
    "registryNo": "2024-001-B",
    "bookNo": "12",
    "pageNo": "45",
    "lineNo": "3"
  },
  "child": {
    "fullName": "Maria Santos",
    "dateOfBirth": "2024-10-15",
    "placeOfBirth": "Manila, Philippines",
    "gender": "Female",
    "address": "123 Main St, Manila",
    "legitimacy": "Legitimate"
  },
  "parents": {
    "father": "Juan Santos",
    "mother": "Ana Santos",
    "marriageInfo": "Manila, January 1, 2020"
  },
  "godparents": {
    "godfather1": "Pedro Cruz",
    "godmother1": "Maria Cruz",
    "godfather2": "Jose Lopez",
    "godmother2": "Carmen Lopez"
  },
  "baptism": {
    "date": "2024-11-13",
    "time": "10:00",
    "place": "St. Mary's Church",
    "minister": "Fr. Antonio Rodriguez"
  },
  "metadata": {
    "remarks": "Special ceremony",
    "certificateIssued": true,
    "staffName": "Sister Maria",
    "dateEncoded": "2024-11-13T10:30:00Z"
  },
  "attachments": [
    {
      "type": "image",
      "path": "/storage/baptism_cert_001.jpg"
    }
  ]
}
```

### **Marriage Record (stored in `notes` field as JSON)**
```javascript
{
  "registry": {
    "registryNo": "2024-001-M",
    "bookNo": "8",
    "pageNo": "22",
    "lineNo": "1"
  },
  "marriage": {
    "date": "2024-11-13",
    "place": "St. Mary's Church",
    "minister": "Fr. Antonio Rodriguez",
    "licenseNo": "ML-2024-001"
  },
  "groom": {
    "fullName": "Juan Santos",
    "birthdate": "1995-05-15",
    "birthplace": "Manila",
    "address": "123 Main St, Manila",
    "father": "Pedro Santos",
    "mother": "Carmen Santos"
  },
  "bride": {
    "fullName": "Ana Cruz",
    "birthdate": "1997-08-20",
    "birthplace": "Quezon City",
    "address": "456 Oak Ave, QC",
    "father": "Miguel Cruz",
    "mother": "Rosa Cruz"
  },
  "witnesses": [
    "Jose Lopez",
    "Maria Lopez"
  ],
  "metadata": {
    "remarks": "Beautiful ceremony",
    "certificateIssued": true,
    "staffName": "Sister Maria",
    "dateEncoded": "2024-11-13T14:30:00Z"
  }
}
```

### **Confirmation Record (stored in `notes` field as JSON)**
```javascript
{
  "registry": {
    "registryNo": "2024-001-C",
    "bookNo": "5",
    "pageNo": "18",
    "lineNo": "7"
  },
  "confirmand": {
    "fullName": "Pedro Santos",
    "birthdate": "2010-03-10",
    "birthplace": "Manila",
    "address": "123 Main St, Manila",
    "gender": "Male",
    "father": "Juan Santos",
    "mother": "Ana Santos"
  },
  "sponsor": {
    "name": "Miguel Cruz",
    "relationship": "Uncle"
  },
  "confirmation": {
    "date": "2024-11-13",
    "place": "St. Mary's Church",
    "minister": "Bishop Rodriguez"
  },
  "metadata": {
    "remarks": "First confirmation of the year",
    "certificateIssued": false,
    "staffName": "Sister Maria",
    "dateEncoded": "2024-11-13T16:00:00Z"
  }
}
```

### **Death Record (stored in `notes` field as JSON)**
```javascript
{
  "registry": {
    "registryNo": "2024-001-D",
    "bookNo": "3",
    "pageNo": "12",
    "lineNo": "4"
  },
  "deceased": {
    "fullName": "Carmen Santos",
    "birthdate": "1950-12-25",
    "address": "123 Main St, Manila",
    "gender": "Female",
    "age": 73,
    "civilStatus": "Married",
    "spouse": "Juan Santos"
  },
  "death": {
    "date": "2024-11-10",
    "place": "Manila General Hospital",
    "cause": "Natural causes"
  },
  "burial": {
    "date": "2024-11-12",
    "place": "Manila Memorial Park",
    "minister": "Fr. Antonio Rodriguez"
  },
  "metadata": {
    "remarks": "Peaceful passing",
    "certificateIssued": true,
    "staffName": "Sister Maria",
    "dateEncoded": "2024-11-13T09:00:00Z"
  }
}
```

---

## **4. CERTIFICATE REQUESTS**

### **Firestore Collection: `certificate_requests`**
```javascript
certificate_requests/{requestId} {
  // Request Info
  id: string,                    // Unique request ID
  recordType: string,            // "Baptism" | "Marriage" | "Confirmation" | "Death"
  
  // Record Details
  recordDetails: {
    fullName: string,            // Person's name
    eventDate: string,           // Date of event
    eventPlace: string           // Place of event
  },
  
  // Request Info
  requestInfo: {
    purpose: string,             // "School" | "Employment" | "Passport" | "Others"
    requesterName: string,       // Person requesting
    contactInfo: string,         // Phone/Email
    preferredPickupDate: string, // When to pickup
    remarks: string,             // Additional notes
    status: string               // "pending" | "processing" | "released"
  },
  
  // Metadata
  metadata: {
    submittedAt: timestamp,      // Submission time
    requestId: string,           // Generated request ID
    parishId: string,            // Parish ID
    processedBy: string,         // Staff who processed
    processedAt: timestamp       // Processing time
  }
}
```

---

## **5. ADMIN FUNCTIONALITY**

### **Firestore Collection: `notifications`**
```javascript
notifications/{notificationId} {
  title: string,                 // Notification title
  body: string,                  // Notification content
  
  // Targeting
  target: string,                // "all" | "role" | "user"
  role: string,                  // Target role (if target = "role")
  userId: string,                // Target user (if target = "user")
  
  // Status
  read: boolean,                 // Read status
  archived: boolean,             // Archive status
  
  // Timestamps
  createdAt: timestamp,          // Creation time
  createdBy: string,             // Admin who created
  
  // Delivery
  sentTo: array,                 // List of user IDs who received
  deliveredAt: timestamp         // Delivery time
}
```

### **Firestore Collection: `audit_logs`**
```javascript
logs/{logId} {
  // Action Info
  action: string,                // Action performed
  details: string,               // Action details
  
  // User Info
  userId: string,                // User who performed action
  userEmail: string,             // User email
  userRole: string,              // User role
  
  // Target Info
  targetType: string,            // "record" | "user" | "system"
  targetId: string,              // ID of target
  
  // Context
  parishId: string,              // Parish context
  ipAddress: string,             // IP address
  userAgent: string,             // Browser/device info
  
  // Timestamp
  timestamp: timestamp,          // When action occurred
  
  // Additional Data
  metadata: object               // Additional context data
}
```

### **Firestore Collection: `settings`**
```javascript
settings/{parishId} {
  // General Settings
  language: string,              // Default language
  timezone: string,              // Parish timezone
  
  // Notifications
  notify: boolean,               // Enable notifications
  emailNotifications: boolean,   // Email notifications
  
  // Backup Settings
  autoBackup: boolean,           // Auto backup enabled
  backupFrequency: string,       // "daily" | "weekly" | "monthly"
  lastBackup: timestamp,         // Last backup time
  
  // System Settings
  maxFileSize: number,           // Max upload size (MB)
  allowedFileTypes: array,       // Allowed file extensions
  
  // Updated Info
  updatedBy: string,             // Last updater
  updatedAt: timestamp           // Last update time
}
```

---

## **6. LOCAL STORAGE (HIVE)**

### **Local Storage Boxes**
```dart
// Records Box (offline storage)
records_box: {
  "record_id": {
    id: string,
    typeIndex: int,              // RecordType enum index
    name: string,
    date: string,                // ISO date string
    imagePath: string,
    parish: string,
    notes: string,               // JSON string
    certificateStatus: int,      // CertificateStatus enum index
    createdAt: string,           // ISO timestamp
    synced: boolean              // Sync status
  }
}

// User Preferences
user_prefs_box: {
  "theme": string,               // "light" | "dark" | "system"
  "language": string,            // Language preference
  "notifications_enabled": boolean,
  "last_sync": string,           // Last sync timestamp
  "offline_mode": boolean        // Offline mode preference
}

// Sync Queue
sync_queue_box: {
  "operation_id": {
    operation: string,           // "create_record" | "update_record" | etc.
    data: object,                // Operation data
    timestamp: string,           // When queued
    retries: int,                // Retry count
    status: string               // "pending" | "processing" | "failed"
  }
}
```

---

## **7. FILE STORAGE STRUCTURE**

### **Firebase Storage Paths**
```
/parishes/{parishId}/
  ├── records/
  │   ├── baptism/
  │   │   ├── 2024/
  │   │   │   ├── {recordId}_certificate.jpg
  │   │   │   └── {recordId}_attachment.pdf
  │   │   └── thumbnails/
  │   ├── marriage/
  │   ├── confirmation/
  │   └── death/
  ├── exports/
  │   ├── csv/
  │   │   └── export_2024-11-13.csv
  │   └── json/
  │       └── backup_2024-11-13.json
  └── temp/
      └── ocr_processing/
```

---

## **8. DATA RELATIONSHIPS**

```
Parish
├── Users (staff, admin)
├── Records
│   ├── Baptism Records
│   ├── Marriage Records
│   ├── Confirmation Records
│   └── Death Records
├── Certificate Requests
├── Notifications
├── Audit Logs
└── Settings

User Authentication (Firebase Auth)
├── User Profile (Firestore)
├── Role-based Access
└── Invite System

Local Storage (Hive)
├── Offline Records
├── Sync Queue
└── User Preferences
```

---

## **9. SECURITY RULES**

### **Firestore Security Rules**
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Users can only access their own profile
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
      allow read: if request.auth != null && 
        get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'admin';
    }
    
    // Records access based on parish and role
    match /records/{recordId} {
      allow read, write: if request.auth != null && 
        resource.data.parishId == get(/databases/$(database)/documents/users/$(request.auth.uid)).data.parishId;
      allow delete: if request.auth != null && 
        get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'admin';
    }
    
    // Certificate requests
    match /certificate_requests/{requestId} {
      allow read, write: if request.auth != null;
    }
    
    // Admin-only collections
    match /audit_logs/{logId} {
      allow read, write: if request.auth != null && 
        get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'admin';
    }
    
    match /notifications/{notificationId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && 
        get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'admin';
    }
  }
}
```

---

## **10. API ENDPOINTS**

### **Backend API Structure**
```
/api/auth/
  POST /login
  POST /register
  POST /forgot-password
  POST /verify-email

/api/records/
  GET    /records
  POST   /records
  PUT    /records/{id}
  DELETE /records/{id}
  PUT    /records/{id}/certificate-status

/api/admin/
  GET    /users
  POST   /users/invite
  PUT    /users/{id}/role
  GET    /analytics
  GET    /audit-logs
  POST   /notifications

/api/certificates/
  POST   /requests
  GET    /requests
  PUT    /requests/{id}/status

/api/ocr/
  POST   /extract-text
  GET    /processing-status/{id}
```

---

## **11. SAMPLE QUERIES**

### **Common Firestore Queries**
```javascript
// Get all records for a parish
db.collection('records')
  .where('parishId', '==', parishId)
  .orderBy('createdAt', 'desc')
  .limit(50)

// Get pending certificate approvals
db.collection('records')
  .where('parishId', '==', parishId)
  .where('certificateStatus', '==', 'pending')
  .orderBy('createdAt', 'desc')

// Get records by type and date range
db.collection('records')
  .where('parishId', '==', parishId)
  .where('type', '==', 'baptism')
  .where('date', '>=', startDate)
  .where('date', '<=', endDate)

// Get user audit trail
db.collection('audit_logs')
  .where('userId', '==', userId)
  .orderBy('timestamp', 'desc')
  .limit(100)

// Get unread notifications for user
db.collection('notifications')
  .where('read', '==', false)
  .where('sentTo', 'array-contains', userId)
  .orderBy('createdAt', 'desc')
```

---

This is the **complete database structure** covering all login forms, staff mobile functionality, and admin mobile features in your Parish Record System.
