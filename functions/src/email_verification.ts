import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import axios from "axios";

// EmailJS configuration
// Set these using Firebase Functions config:
// firebase functions:config:set emailjs.service_id="your_service_id" emailjs.template_id="your_template_id" emailjs.public_key="your_public_key" emailjs.private_key="your_private_key"
const EMAILJS_API_URL = "https://api.emailjs.com/api/v1.0/email/send";

interface EmailJSConfig {
  service_id: string;
  template_id: string;
  user_id: string;
  accessToken?: string;
  template_params: {
    to_email: string;
    to_name: string;
    verification_code: string;
    expiry_time: string;
    [key: string]: string;
  };
}

/**
 * Firestore trigger that sends verification email when a user document
 * is created or updated with a verificationCode field
 */
export const sendVerificationCodeEmail = functions.firestore
  .document("users/{userId}")
  .onWrite(async (change, context) => {
    const { userId } = context.params;
    const after = change.after.data();
    const before = change.before.data();

    // Only send if verificationCode was just added or changed
    if (!after?.verificationCode) {
      return null;
    }

    // Check if code is different from before (to avoid re-sending same code)
    if (before?.verificationCode === after.verificationCode) {
      return null;
    }

    // Check if already verified
    if (after.verificationCodeVerified === true) {
      return null;
    }

    const email = after.email;
    const displayName = after.displayName || email;
    const code = after.verificationCode;
    const expiresAt = after.verificationCodeExpiresAt?.toDate?.() || new Date(Date.now() + 15 * 60 * 1000);

    if (!email) {
      console.log(`No email found for user ${userId}`);
      return null;
    }

    // Get EmailJS config from environment
    const serviceId = process.env.EMAILJS_SERVICE_ID || functions.config().emailjs?.service_id;
    const templateId = process.env.EMAILJS_TEMPLATE_ID || functions.config().emailjs?.template_id;
    const publicKey = process.env.EMAILJS_PUBLIC_KEY || functions.config().emailjs?.public_key;
    const privateKey = process.env.EMAILJS_PRIVATE_KEY || functions.config().emailjs?.private_key;

    if (!serviceId || !templateId || !publicKey) {
      console.log("EmailJS configuration not set. Required: service_id, template_id, public_key");
      console.log(`Verification code for ${email}: ${code}`);
      return null;
    }

    // Prepare EmailJS payload
    const payload: EmailJSConfig = {
      service_id: serviceId,
      template_id: templateId,
      user_id: publicKey,
      accessToken: privateKey,
      template_params: {
        to_email: email,
        to_name: displayName,
        verification_code: code,
        expiry_time: expiresAt.toLocaleString(),
        user_id: userId,
      },
    };

    try {
      // Send email using EmailJS REST API
      const response = await axios.post(EMAILJS_API_URL, payload, {
        headers: {
          "Content-Type": "application/json",
        },
      });

      console.log(`Verification email sent to ${email}. Status:`, response.status);
      
      // Update user document to mark email as sent
      await admin.firestore().collection("users").doc(userId).update({
        verificationEmailSent: true,
        verificationEmailSentAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      
      return null;
    } catch (error) {
      if (axios.isAxiosError(error)) {
        console.error("EmailJS API error:", error.response?.data || error.message);
      } else {
        console.error("Error sending verification email:", error);
      }
      throw error;
    }
  });

/**
 * Callable function to resend verification code
 */
export const resendVerificationCode = functions.https.onCall(async (data, context) => {
  // Verify the user is authenticated
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "User must be authenticated");
  }

  const userId = context.auth.uid;
  const userRef = admin.firestore().collection("users").doc(userId);
  const userDoc = await userRef.get();

  if (!userDoc.exists) {
    throw new functions.https.HttpsError("not-found", "User not found");
  }

  const userData = userDoc.data();
  
  if (userData?.verificationCodeVerified) {
    throw new functions.https.HttpsError("failed-precondition", "User already verified");
  }

  // Generate new 6-digit code
  const code = Math.floor(100000 + Math.random() * 900000).toString();
  const expiresAt = new Date(Date.now() + 15 * 60 * 1000); // 15 minutes

  // Update user document with new code (this will trigger the email)
  await userRef.update({
    verificationCode: code,
    verificationCodeExpiresAt: expiresAt,
    verificationCodeVerified: false,
  });

  return { success: true, message: "Verification code resent" };
});
