const express = require('express');
const { body, validationResult } = require('express-validator');
const { callOcrSpace, overlayToCells } = require('../services/ocrspace_service');

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
    try {
      const json = await callOcrSpace(req.body.imageBase64, { apiKey: process.env.OCRSPACE_API_KEY });
      const { text, cells } = overlayToCells(json);
      return res.json({ success: true, data: { text, cells, engine: 'ocrspace' } });
    } catch (e) {
      return res.status(502).json({ success: false, message: `OCR failed: ${e.message}` });
    }
  },
);

module.exports = router;
