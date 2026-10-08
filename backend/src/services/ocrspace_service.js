const OCR_SPACE_URL = 'https://api.ocr.space/parse/image';

// OCR.space Engine 2 auto-detects the script and sometimes reads Filipino
// handwriting as Cyrillic or Greek ("р - 2 Саливау" for "p - 2 Calivay").
// Parish registers are written in Latin script only, so map the look-alike
// letters back to their Latin twins. Letters with no Latin look-alike are
// left untouched (the reviewer still sees and fixes them).
const HOMOGLYPHS = {
  // Cyrillic letters drawn the same as a Latin letter
  а: 'a', е: 'e', ё: 'e', о: 'o', р: 'p', с: 'c', у: 'y', х: 'x', і: 'i',
  ї: 'i', ј: 'j', ѕ: 's', ԁ: 'd', ԛ: 'q', ԝ: 'w', к: 'k', м: 'm', т: 't',
  в: 'b',
  А: 'A', В: 'B', Е: 'E', Ё: 'E', К: 'K', М: 'M', Н: 'H', О: 'O', Р: 'P',
  С: 'C', Т: 'T', У: 'Y', Х: 'X', І: 'I', Ї: 'I', Ј: 'J', Ѕ: 'S', Ԁ: 'D',
  Ԛ: 'Q', Ԝ: 'W',
  // Greek
  ο: 'o', ρ: 'p', ν: 'v', ι: 'i', κ: 'k', χ: 'x', α: 'a', ε: 'e', τ: 't',
  Α: 'A', Β: 'B', Ε: 'E', Ζ: 'Z', Η: 'H', Ι: 'I', Κ: 'K', Μ: 'M', Ν: 'N',
  Ο: 'O', Ρ: 'P', Τ: 'T', Υ: 'Y', Χ: 'X',
};
const HOMOGLYPH_RE = new RegExp(`[${Object.keys(HOMOGLYPHS).join('')}]`, 'g');

function toLatinLookalikes(text) {
  if (!text) return text;
  return text.replace(HOMOGLYPH_RE, (ch) => HOMOGLYPHS[ch] || ch);
}

function overlayToCells(ocrSpaceJson) {
  const result = (ocrSpaceJson && ocrSpaceJson.ParsedResults && ocrSpaceJson.ParsedResults[0]) || {};
  const text = toLatinLookalikes(result.ParsedText || '');
  const lines = (result.TextOverlay && result.TextOverlay.Lines) || [];
  const cells = [];
  for (const line of lines) {
    for (const w of line.Words || []) {
      const t = toLatinLookalikes((w.WordText || '').trim());
      if (!t) continue;
      cells.push({
        text: t,
        left: Number(w.Left) || 0,
        top: Number(w.Top) || 0,
        width: Number(w.Width) || 0,
        height: Number(w.Height) || 0,
      });
    }
  }
  return { text, cells };
}

async function callOcrSpace(imageBase64, { apiKey, fetchImpl = fetch, engine = '2', detectOrientation = true } = {}) {
  if (!apiKey) throw new Error('OCRSPACE_API_KEY is not configured');
  const params = new URLSearchParams();
  params.append('apikey', apiKey);
  params.append('base64Image', `data:image/jpeg;base64,${imageBase64}`);
  params.append('OCREngine', String(engine));
  params.append('isOverlayRequired', 'true');
  params.append('scale', 'true');
  params.append('detectOrientation', detectOrientation ? 'true' : 'false');
  params.append('isTable', 'true');

  const res = await fetchImpl(OCR_SPACE_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: params.toString(),
  });
  const json = await res.json();
  if (!res.ok) throw new Error(`OCR.space HTTP ${res.status}`);
  if (json.IsErroredOnProcessing) {
    const msg = Array.isArray(json.ErrorMessage)
      ? json.ErrorMessage.join('; ')
      : json.ErrorMessage || 'OCR.space processing error';
    throw new Error(msg);
  }
  return json;
}

module.exports = { overlayToCells, callOcrSpace, toLatinLookalikes, OCR_SPACE_URL };
