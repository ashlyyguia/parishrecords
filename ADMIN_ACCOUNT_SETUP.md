# Admin Account Setup - admin@gmail.com

## Quick Setup Steps:

### 1. Create Admin Account in Firebase Console
1. Go to **Firebase Console** → **Authentication** → **Users**
2. Click **"Add User"**
3. Email: `admin@gmail.com`
4. Password: `admin123` (or your preferred password)
5. Click **"Add User"**

### 2. Set Admin Role in Firestore
1. Go to **Firebase Console** → **Firestore Database**
2. Navigate to `users` collection
3. Find the document with the admin user's UID
4. Add/Update these fields:
   ```json
   {
     "email": "admin@gmail.com",
     "role": "admin",
     "displayName": "Administrator",
     "createdAt": "2024-11-14T00:00:00.000Z",
     "emailVerified": true
   }
   ```

### 3. Test Login
1. Run the app: `flutter run`
2. Login with:
   - Email: `admin@gmail.com`
   - Password: `admin123` (or your set password)
3. Should redirect to `/admin/overview` automatically

## ✅ Expected Behavior:
- `admin@gmail.com` → Redirects to **Admin Dashboard** (`/admin/overview`)
- Any other email → Redirects to **Staff Dashboard** (`/home`)

## 🔧 Troubleshooting:
- If still goes to staff dashboard → Check Firestore user document has `role: "admin"`
- If login fails → Verify account exists in Firebase Authentication
- If network issues → Check internet connection and Firebase config

## 🎯 Admin Features Available:
- User Management
- Certificate Approval
- Analytics & Reports
- Data Backup
- System Settings
