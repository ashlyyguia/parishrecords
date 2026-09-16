const express = require('express');
const { body, validationResult } = require('express-validator');
const { callOcrSpace, overlayToCells } = require('../services/ocrspace_service');
const { isHeic, heicToJpeg } = require('../services/heic_to_jpeg');

function createOcrRouter(deps = {}) {
  const ocr = deps.ocr
    || ((imageBase64) => callOcrSpace(imageBase64, { apiKey: process.env.OCRSPACE_API_KEY }));

  const router = express.Router();

  router.post(
    '/scan',
    [
      body('imageBase64').isString().notEmpty(),
      body('recordType').isIn(['baptism', 'marriage']),
    ],
    async (req, res) => {
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        return res.status(400).json({ success: false, message: 'Invalid request', errors: errors.array() });
      }

      // iPhone uploads are HEIC by default; OCR.space only reads JPEG/PNG/WebP.
      // Convert here before forwarding. An undecodable HEIC is a bad image.
      let imageBase64 = req.body.imageBase64;
      const buffer = Buffer.from(imageBase64, 'base64');
      if (isHeic(buffer)) {
        try {
          imageBase64 = (await heicToJpeg(buffer)).toString('base64');
        } catch (e) {
          return res.status(400).json({ success: false, message: 'That file is not a supported image. Use JPEG, PNG, or WebP.' });
        }
      }

      try {
        const json = await ocr(imageBase64);
        const { text, cells } = overlayToCells(json);
        return res.json({ success: true, data: { text, cells, engine: 'ocrspace' } });
      } catch (e) {
        return res.status(502).json({ success: false, message: `OCR failed: ${e.message}` });
      }
    },
  );

  return router;
}

module.exports = { createOcrRouter, router: createOcrRouter() };
