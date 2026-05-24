import * as functions from "firebase-functions";
import { getAdmin } from "./backend/firebase_admin";

type Candidate = { fullName: string; dateOfBirth: Date | null };
type Match = { recordId: string; score: number; matchedName: string };

function normalizeName(raw: string): string {
  const s = raw.toLowerCase().trim();
  const cleaned = s.replace(/[^a-z0-9\s]/g, " ");
  return cleaned.replace(/\s+/g, " ").trim();
}

function sameYmd(a: Date, b: Date): boolean {
  return (
    a.getFullYear() === b.getFullYear() &&
    a.getMonth() === b.getMonth() &&
    a.getDate() === b.getDate()
  );
}

function nameMatchScore(memberName: string, recordName: string): number {
  const a = normalizeName(memberName);
  const b = normalizeName(recordName);
  if (!a || !b) return 0;
  if (a === b) return 100;
  if (a.includes(b) || b.includes(a)) return 85;

  const aTokens = a.split(" ").filter(Boolean);
  const bTokens = b.split(" ").filter(Boolean);
  if (!aTokens.length || !bTokens.length) return 0;
  const aSet = new Set(aTokens);
  const bSet = new Set(bTokens);
  let common = 0;
  for (const t of aSet) if (bSet.has(t)) common++;
  const minLen = Math.min(aSet.size, bSet.size);
  const ratio = minLen === 0 ? 0 : common / minLen;
  if (ratio >= 0.8) return 80;
  if (ratio >= 0.6) return 70;
  if (ratio >= 0.4) return 55;
  return 0;
}

function tryParseIsoDate(raw: unknown): Date | null {
  if (!raw) return null;
  if (raw instanceof Date) return raw;
  if (typeof raw === "string") {
    const d = new Date(raw);
    return Number.isNaN(d.getTime()) ? null : d;
  }
  if (typeof raw === "object" && raw !== null && "toDate" in raw) {
    const fn = (raw as { toDate?: () => Date }).toDate;
    if (typeof fn === "function") return fn.call(raw);
  }
  return null;
}

function extractBaptism(data: Record<string, unknown>): Candidate[] {
  const text = String(data.text ?? data.name ?? "");
  const notes = data.notes;
  if (!notes || typeof notes !== "string") {
    return [{ fullName: text, dateOfBirth: null }];
  }
  try {
    const decoded = JSON.parse(notes) as Record<string, unknown>;
    const child = decoded.child as Record<string, unknown> | undefined;
    const fullName = String(child?.fullName ?? text);
    const dob = tryParseIsoDate(child?.dateOfBirth);
    return [{ fullName, dateOfBirth: dob }];
  } catch {
    return [{ fullName: text, dateOfBirth: null }];
  }
}

function extractConfirmation(data: Record<string, unknown>): Candidate[] {
  const text = String(data.text ?? data.name ?? "");
  const notes = data.notes;
  if (!notes || typeof notes !== "string") {
    return [{ fullName: text, dateOfBirth: null }];
  }
  try {
    const decoded = JSON.parse(notes) as Record<string, unknown>;
    const confirmand = decoded.confirmand as Record<string, unknown> | undefined;
    const fullName = String(confirmand?.fullName ?? text);
    const dob = tryParseIsoDate(confirmand?.dateOfBirth);
    return [{ fullName, dateOfBirth: dob }];
  } catch {
    return [{ fullName: text, dateOfBirth: null }];
  }
}

function extractMarriage(data: Record<string, unknown>): Candidate[] {
  const text = String(data.text ?? data.name ?? "");
  const notes = data.notes;
  if (!notes || typeof notes !== "string") {
    return [{ fullName: text, dateOfBirth: null }];
  }
  try {
    const decoded = JSON.parse(notes) as Record<string, unknown>;
    const groom = decoded.groom as Record<string, unknown> | undefined;
    const bride = decoded.bride as Record<string, unknown> | undefined;
    const out: Candidate[] = [];
    const groomName = groom?.fullName?.toString().trim();
    if (groomName) out.push({ fullName: groomName, dateOfBirth: null });
    const brideName = bride?.fullName?.toString().trim();
    if (brideName) out.push({ fullName: brideName, dateOfBirth: null });
    if (!out.length) out.push({ fullName: text, dateOfBirth: null });
    return out;
  } catch {
    return [{ fullName: text, dateOfBirth: null }];
  }
}

function extractFuneral(data: Record<string, unknown>): Candidate[] {
  const text = String(data.text ?? data.name ?? "");
  const notes = data.notes;
  if (!notes || typeof notes !== "string") {
    return [{ fullName: text, dateOfBirth: null }];
  }
  try {
    const decoded = JSON.parse(notes) as Record<string, unknown>;
    const deceased =
      (decoded.deceased as Record<string, unknown> | undefined) ??
      (decoded.person as Record<string, unknown> | undefined);
    const fullName = String(deceased?.fullName ?? deceased?.name ?? text);
    const dob = tryParseIsoDate(deceased?.dateOfBirth);
    return [{ fullName, dateOfBirth: dob }];
  } catch {
    return [{ fullName: text, dateOfBirth: null }];
  }
}

async function findBestMatch(
  db: FirebaseFirestore.Firestore,
  collection: string,
  memberName: string,
  memberDob: Date | null,
  extract: (data: Record<string, unknown>) => Candidate[]
): Promise<Match | null> {
  const limit = 200;
  let snap: FirebaseFirestore.QuerySnapshot<Record<string, unknown>>;
  try {
    snap = await db
      .collection(collection)
      .orderBy("created_at", "desc")
      .limit(limit)
      .get();
  } catch {
    snap = await db.collection(collection).limit(limit).get();
  }

  let best: Match | null = null;
  for (const doc of snap.docs) {
    const candidates = extract(doc.data());
    for (const c of candidates) {
      const base = nameMatchScore(memberName, c.fullName);
      if (base === 0) continue;
      let score = base;
      if (memberDob && c.dateOfBirth) {
        score += sameYmd(memberDob, c.dateOfBirth) ? 20 : -20;
      }
      if (!best || score > best.score) {
        best = { recordId: doc.id, score, matchedName: c.fullName };
      }
    }
  }
  return best;
}

async function assertCanManageMember(
  uid: string,
  memberId: string
): Promise<Record<string, unknown>> {
  const admin = getAdmin();
  const db = admin.firestore();
  const memberRef = db.collection("household_members").doc(memberId);
  const memberSnap = await memberRef.get();
  if (!memberSnap.exists) {
    throw new functions.https.HttpsError("not-found", "Member not found");
  }
  const member = memberSnap.data()!;

  const userSnap = await db.collection("users").doc(uid).get();
  const role = String(userSnap.data()?.role ?? "").toLowerCase();
  if (role === "admin" || role === "staff") return member;

  const createdBy = member.created_by ?? member.userId;
  if (createdBy === uid) return member;

  const linkedHouseholdId = userSnap.data()?.linkedHouseholdId;
  if (
    linkedHouseholdId &&
    member.householdId === linkedHouseholdId
  ) {
    return member;
  }

  throw new functions.https.HttpsError(
    "permission-denied",
    "Not allowed to link records for this member"
  );
}

export const autoLinkHouseholdMemberSacraments = functions.https.onCall(
  async (data, context) => {
    if (!context.auth?.uid) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Sign in required"
      );
    }

    const memberId = String(data?.memberId ?? "").trim();
    if (!memberId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "memberId is required"
      );
    }

    const admin = getAdmin();
    const db = admin.firestore();
    const memberData = await assertCanManageMember(context.auth.uid, memberId);

    const memberName = String(
      memberData.fullName ??
        `${memberData.firstName ?? ""} ${memberData.lastName ?? ""}`
    ).trim();
    if (!memberName) {
      return { linked: {}, linkedCount: 0 };
    }

    const birthRaw = memberData.birthDate;
    const memberDob = tryParseIsoDate(birthRaw);

    const baptismMatch = await findBestMatch(
      db,
      "baptism_records",
      memberName,
      memberDob,
      extractBaptism
    );
    const confirmationMatch = await findBestMatch(
      db,
      "confirmation_records",
      memberName,
      memberDob,
      extractConfirmation
    );
    const marriageMatch = await findBestMatch(
      db,
      "marriage_records",
      memberName,
      memberDob,
      extractMarriage
    );
    const funeralMatch = await findBestMatch(
      db,
      "funeral_records",
      memberName,
      memberDob,
      extractFuneral
    );

    const minScore = 70;
    const updates: Record<string, unknown> = {
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    const linked: Record<string, string> = {};
    const linkedSacraments: Record<string, unknown>[] = [];

    async function applyMatch(
      type: string,
      collection: string,
      field: string,
      match: Match | null
    ) {
      if (!match || match.score < minScore) return;
      updates[field] = match.recordId;
      linked[type] = match.recordId;
      let title = match.matchedName;
      let dateIso: string | null = null;
      try {
        const rec = await db.collection(collection).doc(match.recordId).get();
        const data = rec.data();
        if (data) {
          title = String(data.text ?? data.name ?? title);
          const raw = data.created_at ?? data.createdAt;
          const parsed = tryParseIsoDate(raw);
          if (parsed) dateIso = parsed.toISOString();
        }
      } catch (_) {
        /* ignore */
      }
      linkedSacraments.push({
        type,
        recordId: match.recordId,
        title,
        date: dateIso,
        memberName,
      });
    }

    await applyMatch(
      "baptism",
      "baptism_records",
      "baptismRecordId",
      baptismMatch
    );
    await applyMatch(
      "confirmation",
      "confirmation_records",
      "confirmationRecordId",
      confirmationMatch
    );
    await applyMatch(
      "marriage",
      "marriage_records",
      "marriageRecordId",
      marriageMatch
    );
    await applyMatch("death", "funeral_records", "deathRecordId", funeralMatch);

    updates.linkedSacraments = linkedSacraments;

    const metadata = (memberData.metadata as Record<string, unknown>) ?? {};
    updates.metadata = {
      ...metadata,
      autoLinkedSacraments: {
        ranAt: new Date().toISOString(),
        threshold: minScore,
        baptism: baptismMatch,
        confirmation: confirmationMatch,
        marriage: marriageMatch,
        funeral: funeralMatch,
      },
    };

    await db.collection("household_members").doc(memberId).update(updates);

    return {
      linked,
      linkedCount: Object.keys(linked).length,
    };
  }
);
