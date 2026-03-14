module.exports = {
  googleCloudCredentials: process.env.GOOGLE_APPLICATION_CREDENTIALS,
  anthropicApiKey: process.env.ANTHROPIC_API_KEY,

  visionConfig: {
    projectId: process.env.GCP_PROJECT_ID,
    keyFilename: process.env.GOOGLE_APPLICATION_CREDENTIALS
  },

  claudeModel: 'claude-opus-4-20250805',
  claudeMaxTokens: 1024,

  // Rate limiting
  requestsPerMinute: 100,

  // Error handling
  defaultError: 'Receipt parsing failed'
};
