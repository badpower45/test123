/**
 * Notification Service - Real-time Alerts
 * 
 * Sends alerts to Slack and Telegram for high-severity flags
 */

import axios from 'axios';

const SLACK_WEBHOOK_URL = process.env.SLACK_WEBHOOK_URL;
const TELEGRAM_BOT_TOKEN = process.env.TELEGRAM_BOT_TOKEN;
const TELEGRAM_CHAT_ID = process.env.TELEGRAM_CHAT_ID;

// ============================================================================
// SLACK INTEGRATION
// ============================================================================

export async function sendSlackAlert(message: string, severity: number) {
  if (!SLACK_WEBHOOK_URL) {
    console.log('[Slack] Webhook URL not configured, skipping alert');
    return;
  }
  
  const color = severity > 0.8 ? '#FF0000' :  // Red - Critical
                severity > 0.5 ? '#FFA500' :  // Orange - Warning
                '#FFFF00';                    // Yellow - Info
  
  const emoji = severity > 0.8 ? '🚨' :
                severity > 0.5 ? '⚠️' : 'ℹ️';
  
  const payload = {
    attachments: [{
      color,
      title: `${emoji} BLV Security Alert`,
      text: message,
      footer: 'Oldies Workers System',
      footer_icon: 'https://platform.slack-edge.com/img/default_application_icon.png',
      ts: Math.floor(Date.now() / 1000)
    }]
  };
  
  try {
    await axios.post(SLACK_WEBHOOK_URL, payload);
    console.log('[Slack] Alert sent successfully');
  } catch (error: any) {
    console.error('[Slack] Failed to send alert:', error.message);
  }
}

// ============================================================================
// TELEGRAM INTEGRATION
// ============================================================================

export async function sendTelegramAlert(message: string, severity: number = 0.5) {
  if (!TELEGRAM_BOT_TOKEN || !TELEGRAM_CHAT_ID) {
    console.log('[Telegram] Bot not configured, skipping alert');
    return;
  }
  
  const emoji = severity > 0.8 ? '🚨' :
                severity > 0.5 ? '⚠️' : 'ℹ️';
  
  const url = `https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage`;
  
  try {
    await axios.post(url, {
      chat_id: TELEGRAM_CHAT_ID,
      text: `${emoji} *BLV Alert*\n\n${message}`,
      parse_mode: 'Markdown'
    });
    console.log('[Telegram] Alert sent successfully');
  } catch (error: any) {
    console.error('[Telegram] Failed to send alert:', error.message);
  }
}

// ============================================================================
// EMAIL NOTIFICATION (Optional)
// ============================================================================

export async function sendEmailAlert(
  to: string,
  subject: string,
  body: string
) {
  // TODO: Integrate with SendGrid, AWS SES, or similar
  console.log('[Email] Alert:', { to, subject, body });
}

// ============================================================================
// UNIFIED ALERT DISPATCHER
// ============================================================================

export async function sendAlert(
  message: string,
  severity: number,
  channels: ('slack' | 'telegram' | 'email')[] = ['slack', 'telegram']
) {
  const promises = [];
  
  if (channels.includes('slack')) {
    promises.push(sendSlackAlert(message, severity));
  }
  
  if (channels.includes('telegram')) {
    promises.push(sendTelegramAlert(message, severity));
  }
  
  // Run all notifications in parallel
  await Promise.allSettled(promises);
}
