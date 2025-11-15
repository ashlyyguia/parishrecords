# 🚨 QUICK ADMIN SETUP - Fix Dashboard Access

## **IMMEDIATE SOLUTION:**

### **Step 1: Create Admin Account in Firebase Console**
1. Go to **Firebase Console** → **Authentication** → **Users**
2. Click **"Add User"**
3. **Email:** `admin@gmail.com`
4. **Password:** `admin123` (or your choice)
5. Click **"Add User"**

### **Step 2: Set Admin Role in Firestore**
1. Go to **Firebase Console** → **Firestore Database**
2. Go to **`users`** collection
3. Find the document with admin user's UID (or create new document with the UID)
4. Set these fields:
   ```json
   {
     "email": "admin@gmail.com",
     "role": "admin",
     "displayName": "Administrator",
     "createdAt": "2024-11-14T00:00:00.000Z",
     "emailVerified": true
   }
   ```

### **Step 3: Test Login**
1. **Login with:** `admin@gmail.com` / `admin123`
2. **Should redirect to:** `/admin/overview` (Admin Dashboard)

---

## **🔍 DEBUGGING STEPS:**

### **Check Debug Output:**
When you login, check the Flutter console for these debug messages:
```
Admin Access Check:
Email: admin@gmail.com
Role: admin (or staff)
Is Email Admin: true
Is Role Admin: true (or false)
```

### **If Role Shows 'staff':**
- The Firestore document doesn't have `role: "admin"`
- Go back to Step 2 and set the role properly

### **If Still Goes to Staff Dashboard:**
- Clear app data and restart
- Check if email is exactly `admin@gmail.com` (no spaces)

---

## **🎯 EXPECTED BEHAVIOR:**

- **`admin@gmail.com`** → **Admin Dashboard** (`/admin/overview`)
- **Any other email** → **Staff Dashboard** (`/home`)

---

## **⚡ ALTERNATIVE: Temporary Admin Button**

If you need immediate access, I can add a temporary admin button to the login screen for testing.

**Would you like me to add a temporary admin access button?**
