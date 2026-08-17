const OCR_SPACE_URL = 'https://api.ocr.space/parse/image';

function overlayToCells(ocrSpaceJson) {
  const result = (ocrSpaceJson && ocrSpaceJson.ParsedResults && ocrSpaceJson.ParsedResults[0]) || {};
  const text = result.ParsedText || '';
  const lines = (result.TextOverlay && result.TextOverlay.Lines) || [];
  const cells = [];
  for (const line of lines) {
    for (const w of line.Words || []) {
      const t = (w.WordText || '').trim();
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

async function callOcrSpace(imageBase64, { apiKey, fetchImpl = fetch } = {}) {
  if (!apiKey) throw new Error('OCRSPACE_API_KEY is not configured');
  const params = new URLSearchParams();
  params.append('apikey', apiKey);
  params.append('base64Image', `data:image/jpeg;base64,${imageBase64}`);
  params.append('OCREngine', '2');
  params.append('isOverlayRequired', 'true');
  params.append('scale', 'true');
  params.append('detectOrientation', 'true');
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

module.exports = { overlayToCells, callOcrSpace, OCR_SPACE_URL };
