// Donation seeder v2 — the "General" category is retired. Aligned with how the
// app records walk-in donations (DonationsRepository.createManualCashDonation):
// cash only, categories Tithes / Projects / Outreach, source manual_cash,
// recorded by the Finance account. Names are fictional. No passwords: auth
// comes from `firebase login` (see fs.js).
//
// It reuses the document ids of seed_donations.js (seed_cash_don_001...), so
// running it REPLACES that earlier batch in place, including its "General"
// rows, instead of adding to it.
//
//   node seed_donations_v2.js --dry-run       preview counts and totals, write nothing
//   node seed_donations_v2.js [--count 150]   write (same IDs each run -> overwrite, not duplicate)
//   node seed_donations_v2.js --clean         delete the donations written by this script
//                                             or by the earlier seed_donations.js
const f = require('./fs.js');

const TAG = 'donations-cash-2026-v2';
const PREVIOUS_TAG = 'donations-cash-2026'; // seed_donations.js (had "General")
const DOCS = 'projects/holyparish/databases/(default)/documents';
const FINANCE_EMAIL = 'gonzagaprince919@gmail.com';

const args = process.argv.slice(2);
const has = (a) => args.includes(a);
const COUNT = Number(args[args.indexOf('--count') + 1]) || 150;

// ---------- deterministic random (same data every run) ----------
let _s = 20261011;
const rnd = () => { _s = (_s * 1664525 + 1013904223) % 4294967296; return _s / 4294967296; };
const pick = (a) => a[Math.floor(rnd() * a.length)];
const int = (a, b) => a + Math.floor(rnd() * (b - a + 1));
const pad = (n, w = 2) => String(n).padStart(w, '0');
const weighted = (pairs) => { let r = rnd() * pairs.reduce((t, [, w]) => t + w, 0); for (const [v, w] of pairs) { if ((r -= w) < 0) return v; } return pairs[0][0]; };

// The three categories the Record Donation form offers, with realistic
// shares and amount ranges (PHP). Tithes also takes the small, loose gifts
// that used to go to "General".
const CATEGORIES = [
  ['Tithes', 58, [20, 50, 100, 100, 200, 300, 500, 500, 1000, 1000, 1500, 2000, 3000, 5000]],
  ['Projects', 25, [200, 500, 500, 1000, 1000, 1500, 2000, 3000, 5000]],
  ['Outreach', 17, [100, 200, 300, 500, 500, 1000, 1500]],
];
const FIRST = ['Jose', 'Juan', 'Mark', 'Christian', 'Rodel', 'Arnel', 'Ramil', 'Noel', 'Edgar', 'Vicente', 'Joel', 'Paolo', 'Gabriel', 'Dante', 'Maria', 'Ana', 'Rosalie', 'Marites', 'Jocelyn', 'Lorna', 'Cristina', 'Michelle', 'Rowena', 'Grace', 'Erlinda', 'Teresa', 'Divina', 'Liezel', 'Mylene', 'Remedios'];
const LAST = ['Abellana', 'Bacus', 'Cagas', 'Dumdum', 'Enriquez', 'Fuentes', 'Gonzaga', 'Hinayon', 'Jumawan', 'Labrador', 'Mendoza', 'Nacua', 'Ocampo', 'Pagaran', 'Quiamco', 'Rosales', 'Salazar', 'Tabanao', 'Ubaldo', 'Velasco', 'Yap', 'Zamora', 'Amper', 'Cuizon', 'Estrada', 'Flores', 'Lumapas', 'Navarro', 'Villarin', 'Ybañez'];
// A small set of regular parishioners who give repeatedly, plus walk-ins.
const REGULARS = Array.from({ length: 18 }, () => `${pick(FIRST)} ${pick(LAST)}`);

function enc(v) {
  if (v === null || v === undefined) return { nullValue: null };
  if (v instanceof Date) return { timestampValue: v.toISOString() };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (typeof v === 'number') return { doubleValue: v }; // the app stores amounts as doubles
  if (typeof v === 'string') return { stringValue: v };
  return { mapValue: { fields: Object.fromEntries(Object.entries(v).map(([k, x]) => [k, enc(x)])) } };
}

async function commit(writes) {
  const url = `https://firestore.googleapis.com/v1/${DOCS}:commit`;
  for (let i = 0; i < writes.length; i += 400) {
    await f.api(url, { method: 'POST', body: JSON.stringify({ writes: writes.slice(i, i + 400) }) });
  }
}

async function deleteWhere(pred) {
  const all = await f.list('donations', 300);
  const ids = all.filter(pred).map((d) => d._id || d.id);
  await commit(ids.map((id) => ({ delete: `${DOCS}/donations/${id}` })));
  return ids.length;
}

(async () => {
  if (has('--clean')) {
    const n = await deleteWhere((d) => d.seed_batch === TAG || d.seed_batch === PREVIOUS_TAG);
    console.log(`Deleted ${n} donations written by this seeder.`);
    return;
  }

  const finance = (await f.lookupUsers([FINANCE_EMAIL]))[0];
  if (!finance && !has('--dry-run')) throw new Error(`Finance account ${FINANCE_EMAIL} not found`);

  // Spread across 1 Jan 2026 .. today, more on Sundays (Mass collections).
  const start = new Date('2026-01-01T00:00:00+08:00').getTime();
  const end = Date.now();
  const docs = [];
  for (let i = 1; i <= COUNT; i++) {
    let t = new Date(start + rnd() * (end - start));
    if (rnd() < 0.55) t = new Date(t.getTime() - t.getDay() * 864e5); // snap to that week's Sunday
    if (t.getTime() < start) t = new Date(start + int(0, 6) * 864e5);
    t.setHours(int(7, 16), int(0, 59), 0, 0);

    const category = weighted(CATEGORIES.map(([c, w]) => [c, w]));
    const amount = pick(CATEGORIES.find(([c]) => c === category)[2]);
    const anonymous = rnd() < 0.12;
    const donor = rnd() < 0.6 ? pick(REGULARS) : `${pick(FIRST)} ${pick(LAST)}`;
    // Older entries are mostly reconciled; the last ~2 weeks mostly pending.
    const ageDays = (end - t.getTime()) / 864e5;
    const reconciled = ageDays > 14 ? rnd() < 0.95 : rnd() < 0.3;

    docs.push({
      id: `seed_cash_don_${pad(i, 3)}`,
      data: {
        // exactly the fields DonationsRepository.create() writes for a manual cash donation
        amount,
        method: 'cash',
        campaign: category,
        donor_name: anonymous ? null : donor,
        anonymous,
        donor_id: finance ? finance.uid : 'DRY_RUN',
        reconciled,
        online: false,
        source: 'manual_cash',
        created_at: t,
        // set by the app after notifying Finance / reconciling
        finance_notified: true,
        ...(reconciled ? { updated_at: new Date(Math.min(end, t.getTime() + int(1, 5) * 864e5)) } : {}),
        seed_batch: TAG,
      },
    });
  }

  // Summary
  const by = {};
  for (const { data } of docs) {
    const b = (by[data.campaign] ||= { n: 0, total: 0 });
    b.n++; b.total += data.amount;
  }
  const total = docs.reduce((t, d) => t + d.data.amount, 0);
  console.log(`${docs.length} cash donations, ₱${total.toLocaleString('en-PH')} total, ${docs.filter((d) => d.data.reconciled).length} reconciled`);
  for (const [c, { n, total: tt }] of Object.entries(by)) console.log(`  ${c.padEnd(9)} ${String(n).padStart(4)}  ₱${tt.toLocaleString('en-PH')}`);
  const months = {};
  for (const { data } of docs) { const m = data.created_at.toISOString().slice(0, 7); months[m] = (months[m] || 0) + 1; }
  console.log('  by month:', Object.entries(months).sort().map(([m, n]) => `${m.slice(5)}:${n}`).join(' '));

  if (has('--dry-run')) { console.log('Dry run: nothing written.'); return; }

  // Ids line up with seed_donations.js, so its rows are overwritten below.
  // If that batch was larger than this one, remove the leftovers.
  const ids = new Set(docs.map((d) => d.id));
  const extra = await deleteWhere((d) => d.seed_batch === PREVIOUS_TAG && !ids.has(d._id || d.id));
  if (extra) console.log(`Removed ${extra} leftover rows from the previous seed.`);
  await commit(docs.map(({ id, data }) => ({
    update: { name: `${DOCS}/donations/${id}`, fields: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, enc(v)])) },
  })));
  console.log(`Wrote ${docs.length} donations (tag ${TAG}).`);
})().catch((e) => { console.error(e.message || e); process.exit(1); });
