/**
 * Fraud Alert Dispatcher
 *
 * Listens for fraud alerts from database and dispatches notifications
 * to managers, owners, and external channels (Slack, Telegram)
 */
import { sendAlert } from './notification-service.js';
// ============================================================================
// FRAUD ALERT FORMATTER
// ============================================================================
function formatFraudAlertMessage(alert) {
    const { details, alert_type, total_score, severity } = alert;
    const severityText = severity > 0.8 ? 'CRITICAL' :
        severity > 0.5 ? 'WARNING' : 'INFO';
    const employeeName = details.employee_name || 'Unknown Employee';
    const branchName = details.branch_name || 'Unknown Branch';
    const scoreText = total_score !== null ? `${total_score}/100` : 'N/A';
    let message = `*${severityText}*: Fraud Detection Alert\n\n`;
    message += `📛 Alert Type: ${alert_type.replace('_', ' ')}\n`;
    message += `👤 Employee: ${employeeName}\n`;
    message += `🏢 Branch: ${branchName}\n`;
    message += `📊 BLV Score: ${scoreText}\n`;
    if (details.validation_type) {
        message += `🔍 Type: ${details.validation_type}\n`;
    }
    if (details.timestamp) {
        const timestamp = new Date(details.timestamp);
        message += `⏰ Time: ${timestamp.toLocaleString()}\n`;
    }
    // Add detailed scores if available
    const scores = [];
    if (details.wifi_score !== undefined)
        scores.push(`WiFi: ${details.wifi_score}`);
    if (details.gps_score !== undefined)
        scores.push(`GPS: ${details.gps_score}`);
    if (details.cell_score !== undefined)
        scores.push(`Cell: ${details.cell_score}`);
    if (details.sound_score !== undefined)
        scores.push(`Sound: ${details.sound_score}`);
    if (details.motion_score !== undefined)
        scores.push(`Motion: ${details.motion_score}`);
    if (scores.length > 0) {
        message += `\n📈 Component Scores:\n${scores.join(', ')}`;
    }
    return message;
}
// ============================================================================
// FRAUD ALERT HANDLER
// ============================================================================
export async function handleFraudAlert(alert) {
    try {
        console.log(`[Fraud Alert] Processing alert ${alert.id} - ${alert.alert_type}`);
        // Format the message
        const message = formatFraudAlertMessage(alert);
        // Determine notification channels based on severity
        const channels = [];
        if (alert.severity > 0.8) {
            // Critical - send to all channels
            channels.push('slack', 'telegram');
        }
        else if (alert.severity > 0.5) {
            // Warning - send to Slack
            channels.push('slack');
        }
        else {
            // Info - log only
            console.log(`[Fraud Alert] Low severity alert, logging only`);
            console.log(message);
            return;
        }
        // Send notifications
        await sendAlert(message, alert.severity, channels);
        console.log(`[Fraud Alert] Notifications sent successfully for alert ${alert.id}`);
    }
    catch (error) {
        console.error(`[Fraud Alert] Failed to process alert:`, error.message);
    }
}
// ============================================================================
// BATCH PROCESSING
// ============================================================================
export async function processPendingAlerts(getUnresolvedAlerts) {
    try {
        const alerts = await getUnresolvedAlerts();
        if (alerts.length === 0) {
            console.log('[Fraud Alert] No pending alerts to process');
            return;
        }
        console.log(`[Fraud Alert] Processing ${alerts.length} pending alert(s)`);
        // Process alerts in parallel
        await Promise.allSettled(alerts.map(alert => handleFraudAlert(alert)));
    }
    catch (error) {
        console.error('[Fraud Alert] Batch processing failed:', error.message);
    }
}
const DEFAULT_PREFERENCES = {
    enabled: true,
    min_severity: 0.5,
    channels: ['slack', 'telegram'],
};
export function shouldSendNotification(alert, preferences = DEFAULT_PREFERENCES) {
    if (!preferences.enabled) {
        return false;
    }
    if (alert.severity < preferences.min_severity) {
        return false;
    }
    // Check quiet hours if configured
    if (preferences.quiet_hours) {
        const now = new Date();
        const currentTime = `${now.getHours().toString().padStart(2, '0')}:${now.getMinutes().toString().padStart(2, '0')}`;
        if (currentTime >= preferences.quiet_hours.start &&
            currentTime <= preferences.quiet_hours.end) {
            // During quiet hours, only send critical alerts
            return alert.severity > 0.9;
        }
    }
    return true;
}
// ============================================================================
// EXPORT
// ============================================================================
export default {
    handleFraudAlert,
    processPendingAlerts,
    formatFraudAlertMessage,
    shouldSendNotification,
};
