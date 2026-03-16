const axios = require('axios');
const vision = require('@google-cloud/vision');
const Anthropic = require('@anthropic-ai/sdk');

// Initialize clients
const visionClient = new vision.ImageAnnotatorClient({
  keyFilename: process.env.GOOGLE_APPLICATION_CREDENTIALS
});
const anthropic = new Anthropic({
  apiKey: process.env.ANTHROPIC_API_KEY
});

exports.handler = async (event) => {
  try {
    // Parse request
    const { imageBase64, userId } = JSON.parse(event.body);

    if (!imageBase64) {
      return {
        statusCode: 400,
        body: JSON.stringify({ error: 'imageBase64 is required' })
      };
    }

    // Step 1: Google Cloud Vision OCR
    console.log('[INFO] Starting Google Cloud Vision OCR...');
    const buffer = Buffer.from(imageBase64, 'base64');
    console.log('[DEBUG] Image buffer size:', buffer.length, 'bytes');

    const visionResponse = await visionClient.textDetection({
      image: { content: buffer }
    });
    const ocrText = visionResponse[0].fullTextAnnotation?.text || '';

    console.log('[INFO] Google Cloud Vision OCR completed');
    console.log('[DEBUG] OCR text length:', ocrText.length, 'characters');
    console.log('[DEBUG] OCR text (first 300 chars):', ocrText.substring(0, 300));

    if (!ocrText) {
      console.error('[ERROR] No text extracted from receipt image');
      return {
        statusCode: 400,
        body: JSON.stringify({ error: 'Unable to extract text from receipt image' })
      };
    }

    // Step 2: Claude API - Structure extraction
    console.log('[INFO] Starting Claude API for structure extraction...');
    const claudePrompt = `Extract structured data from this receipt OCR text. Return ONLY valid JSON (no markdown, no code blocks).

OCR Text:
${ocrText}

Return this exact JSON structure (do NOT include rawText field - it will be added automatically):
{
  "shopName": "string (the store/shop name)",
  "date": "YYYY-MM-DD (the receipt date, not scan date)",
  "total": number (total amount, or null if not found),
  "currency": "string (3-letter code like USD, EUR, GBP, or null if not found)",
  "lineItems": [
    {
      "name": "string",
      "quantity": number or null,
      "unitPrice": number or null,
      "totalPrice": number or null
    }
  ]
}

If any field cannot be determined, use null.`;

    console.log('[DEBUG] Claude prompt length:', claudePrompt.length, 'characters');

    const claudeResponse = await anthropic.messages.create({
      model: 'claude-haiku-4-5-20251001',
      max_tokens: 1024,
      messages: [{ role: 'user', content: claudePrompt }]
    });

    console.log('[INFO] Claude API response received');
    console.log('[DEBUG] Claude response stop reason:', claudeResponse.stop_reason);
    console.log('[DEBUG] Claude response content type:', claudeResponse.content[0]?.type);
    console.log('[DEBUG] Claude response token usage:', { input_tokens: claudeResponse.usage?.input_tokens, output_tokens: claudeResponse.usage?.output_tokens });

    // Parse Claude response
    let receiptData;
    let responseText = '';
    try {
      responseText = claudeResponse.content[0].type === 'text'
        ? claudeResponse.content[0].text
        : '';

      console.log('[DEBUG] Raw Claude response (first 500 chars):', responseText.substring(0, 500));
      console.log('[DEBUG] Raw Claude response length:', responseText.length);

      // Strip markdown code blocks if present (Haiku sometimes returns ```json...```)
      // Handle various markdown formats: ```json, ```JSON, ``` json, etc.
      const jsonMatch = responseText.match(/```\s*(?:json|JSON)?\s*([\s\S]*?)```/);
      if (jsonMatch) {
        responseText = jsonMatch[1].trim();
        console.log('[DEBUG] Extracted JSON from markdown code block, length:', responseText.length);
      }

      // Also handle case where there's just backticks without closing
      // (fallback for malformed responses)
      if (responseText.trim().startsWith('```')) {
        responseText = responseText
          .replace(/^```\s*(?:json|JSON)?\s*/i, '')
          .replace(/```\s*$/,'')
          .trim();
        console.log('[DEBUG] Stripped unmatched backticks, length:', responseText.length);
      }

      console.log('[DEBUG] Final text to parse (first 200 chars):', responseText.substring(0, 200));

      receiptData = JSON.parse(responseText);
    } catch (parseError) {
      console.error('[ERROR] JSON parse failed:', parseError.message);
      return {
        statusCode: 500,
        body: JSON.stringify({ error: 'Failed to parse Claude response: ' + parseError.message })
      };
    }

    // Always use the actual OCR text as rawText (Claude shouldn't include it to avoid escaping issues)
    receiptData.rawText = ocrText;

    return {
      statusCode: 200,
      body: JSON.stringify(receiptData)
    };

  } catch (error) {
    console.error('Error:', error);
    return {
      statusCode: 500,
      body: JSON.stringify({ error: error.message })
    };
  }
};
