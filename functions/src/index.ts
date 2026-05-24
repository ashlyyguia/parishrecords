import * as functions from "firebase-functions";
import express from "express";
import cors from "cors";
import helmet from "helmet";
import rateLimit from "express-rate-limit";

// Import email verification functions
export { sendVerificationCodeEmail, resendVerificationCode } from "./email_verification";
export { autoLinkHouseholdMemberSacraments } from "./auto_link_member_sacraments";

// Import backend routes
import { router as userDashboardRoutes } from "./backend/routes/user_dashboard_firestore";
import { router as usersRoutes } from "./backend/routes/users_firestore";
import { router as adminRoutes } from "./backend/routes/admin_firestore";
import { router as recordsRoutes } from "./backend/routes/records_firestore";
import { router as requestsRoutes } from "./backend/routes/requests_firestore";
import { router as notificationsRoutes } from "./backend/routes/notifications_firestore";
import { router as staffRoutes } from "./backend/routes/staff_firestore";
import { router as ocrJobsRoutes } from "./backend/routes/ocr_jobs_firestore";
import { router as eventsRoutes } from "./backend/routes/events_firestore";
import { router as bookingsRoutes } from "./backend/routes/bookings_firestore";
import { router as financeRoutes } from "./backend/routes/finance_firestore";
import { router as donationsRoutes } from "./backend/routes/donations_firestore";
import { router as reportsFinancialRoutes } from "./backend/routes/reports_financial_firestore";
import { router as userSelfRoutes } from "./backend/routes/user_self_firestore";
import { router as sacramentsRoutes } from "./backend/routes/sacraments_firestore";
import { router as appointmentsRoutes } from "./backend/routes/appointments_firestore";
import { verifyFirebaseToken } from "./backend/middleware/auth";

const app = express();

// Security middleware
app.use(helmet({
  contentSecurityPolicy: false,
  crossOriginEmbedderPolicy: false,
}));

// CORS configuration
app.use(cors({
  origin: true,
  credentials: true,
}));

// Rate limiting
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100 // limit each IP to 100 requests per windowMs
});
app.use(limiter);

// Body parsing middleware
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true }));

// Health check endpoint
app.get('/health', (req: express.Request, res: express.Response) => {
  res.json({ 
    status: 'OK', 
    timestamp: new Date().toISOString(),
    database: 'firebase'
  });
});

// Firebase token verification for all API routes
app.use('/api', verifyFirebaseToken);

// API routes
app.use('/api/records', recordsRoutes);
app.use('/api/users', usersRoutes);
app.use('/api/admin', adminRoutes);
app.use('/api/requests', requestsRoutes);
app.use('/api/notifications', notificationsRoutes);
app.use('/api/staff', staffRoutes);
app.use('/api/ocr_jobs', ocrJobsRoutes);
app.use('/api/events', eventsRoutes);
app.use('/api/bookings', bookingsRoutes);
app.use('/api/finance', financeRoutes);
app.use('/api/donations', donationsRoutes);
app.use('/api/reports', reportsFinancialRoutes);
app.use('/api/users', userDashboardRoutes);
app.use('/api/users', userSelfRoutes);
app.use('/api/sacraments', sacramentsRoutes);
app.use('/api/appointments', appointmentsRoutes);

// Error handling middleware
app.use((err: any, req: express.Request, res: express.Response, next: express.NextFunction) => {
  console.error('Error:', err);
  res.status(err.status || 500).json({
    error: 'Internal Server Error'
  });
});

// 404 handler
app.use('*', (req: express.Request, res: express.Response) => {
  res.status(404).json({ error: 'Route not found' });
});

// Export the API as a Firebase Function
export const api = functions.https.onRequest(app);
