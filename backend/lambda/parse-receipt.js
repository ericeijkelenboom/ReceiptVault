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
    const buffer = Buffer.from(imageBase64, 'base64');
    const visionResponse = await visionClient.textDetection({
      image: { content: buffer }
    });
    const ocrText = visionResponse[0].fullTextAnnotation?.text || '';

    if (!ocrText) {
      return {
        statusCode: 400,
        body: JSON.stringify({ error: 'Unable to extract text from receipt image' })
      };
    }

    // Step 2: Claude API - Structure extraction
    const claudePrompt = `Extract structured data from this receipt OCR text. Return ONLY valid JSON (no markdown, no code blocks).

OCR Text:
${ocrText}

Return this exact JSON structure:
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
  ],
  "rawText": "the full OCR text"
}

If any field cannot be determined, use null.`;

    const claudeResponse = await anthropic.messages.create({
      model: 'claude-3-5-haiku-20241022',
      max_tokens: 1024,
      messages: [{ role: 'user', content: claudePrompt }]
    });

    // Parse Claude response
    let receiptData;
    try {
      const responseText = claudeResponse.content[0].type === 'text'
        ? claudeResponse.content[0].text
        : '';
      receiptData = JSON.parse(responseText);
    } catch (parseError) {
      return {
        statusCode: 500,
        body: JSON.stringify({ error: 'Failed to parse Claude response: ' + parseError.message })
      };
    }

    // Ensure rawText is set
    if (!receiptData.rawText) {
      receiptData.rawText = ocrText;
    }

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
