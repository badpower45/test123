/**
 * Drift Detection Service
 * 
 * Detects when branch environmental baselines have drifted significantly
 * from current conditions, indicating need for recalibration
 */

import { db } from '../db.js';
import { 
  pulses,
  branchEnvironmentBaselines,
} from '../../shared/schema.js';
import { eq, sql, gte, and, isNotNull } from 'drizzle-orm';
import { sendAlert } from './notification-service.js';

// ============================================================================
// DRIFT DETECTION
// ============================================================================

export interface DriftReport {
  hasDrift: boolean;
  reason?: string;
  wifiDrift?: number;
  batteryDrift?: number;
  motionDrift?: number;
  recommendation?: 'OK' | 'RECALIBRATE_BASELINE' | 'INSUFFICIENT_DATA';
}

export async function detectBaselineDrift(
  branchId: string,
  timeSlot: string
): Promise<DriftReport> {
  console.log(`[BLV Drift] Checking drift for branch ${branchId}, time slot: ${timeSlot}`);
  
  // Get recent pulses (last 100)
  const recentPulses = await db
    .select({
      wifiCount: pulses.wifiCount,
      batteryLevel: pulses.batteryLevel,
      accelVariance: pulses.accelVariance,
    })
    .from(pulses)
    .where(and(
      eq(pulses.branchId, branchId),
      isNotNull(pulses.wifiCount)
    ))
    .orderBy(sql`timestamp DESC`)
    .limit(100);
  
  if (recentPulses.length < 50) {
    return { 
      hasDrift: false, 
      reason: 'INSUFFICIENT_DATA',
      recommendation: 'INSUFFICIENT_DATA'
    };
  }
  
  // Get current baseline
  const baseline = await db.query.branchEnvironmentBaselines.findFirst({
    where: and(
      eq(branchEnvironmentBaselines.branchId, branchId),
      eq(branchEnvironmentBaselines.timeSlot, timeSlot)
    )
  });
  
  if (!baseline) {
    return { 
      hasDrift: true, 
      reason: 'NO_BASELINE',
      recommendation: 'RECALIBRATE_BASELINE'
    };
  }
  
  // Calculate averages from recent data
  const avgWifiCount = recentPulses.reduce((sum, p) => sum + (p.wifiCount || 0), 0) / recentPulses.length;
  const avgBattery = recentPulses.reduce((sum, p) => sum + (p.batteryLevel || 0), 0) / recentPulses.length;
  const avgMotion = recentPulses.reduce((sum, p) => sum + (p.accelVariance || 0), 0) / recentPulses.length;
  
  // Calculate drift (absolute difference)
  const wifiDrift = Math.abs(avgWifiCount - baseline.avgWifiCount);
  const batteryDrift = Math.abs(avgBattery - baseline.avgBatteryLevel);
  const motionDrift = Math.abs(avgMotion - baseline.avgAccelVariance);
  
  // Thresholds
  const WIFI_THRESHOLD = 3;        // ±3 networks
  const BATTERY_THRESHOLD = 0.15;  // ±15%
  const MOTION_THRESHOLD = 0.3;    // ±0.3 variance
  
  const driftDetected = 
    wifiDrift > WIFI_THRESHOLD ||
    batteryDrift > BATTERY_THRESHOLD ||
    motionDrift > MOTION_THRESHOLD;
  
  if (driftDetected) {
    const driftType = wifiDrift > WIFI_THRESHOLD ? 'WiFi' :
                     batteryDrift > BATTERY_THRESHOLD ? 'Battery' : 'Motion';
    
    const message = `
🔄 **Baseline Drift Detected**

**Branch ID:** ${branchId}
**Time Slot:** ${timeSlot}
**Drift Type:** ${driftType}

**Details:**
• WiFi Networks: ${baseline.avgWifiCount.toFixed(1)} → ${avgWifiCount.toFixed(1)} (drift: ${wifiDrift.toFixed(1)})
• Battery Level: ${(baseline.avgBatteryLevel * 100).toFixed(0)}% → ${(avgBattery * 100).toFixed(0)}% (drift: ${(batteryDrift * 100).toFixed(0)}%)
• Motion Variance: ${baseline.avgAccelVariance.toFixed(2)} → ${avgMotion.toFixed(2)} (drift: ${motionDrift.toFixed(2)})

**Action Required:** Recalibrate baseline for this branch
    `.trim();
    
    // Send alert (severity 0.7 - warning level)
    await sendAlert(message, 0.7, ['slack', 'telegram']);
    
    console.log(`[BLV Drift] Drift detected - ${driftType}:`, {
      wifiDrift,
      batteryDrift,
      motionDrift
    });
  }
  
  return {
    hasDrift: driftDetected,
    wifiDrift,
    batteryDrift,
    motionDrift,
    recommendation: driftDetected ? 'RECALIBRATE_BASELINE' : 'OK'
  };
}

/**
 * Schedule drift detection for all branches
 */
export async function detectAllBranchDrift(): Promise<void> {
  console.log('[BLV Drift] Running drift detection for all branches...');
  
  // Get all unique branch baselines
  const baselines = await db
    .selectDistinct({
      branchId: branchEnvironmentBaselines.branchId,
      timeSlot: branchEnvironmentBaselines.timeSlot
    })
    .from(branchEnvironmentBaselines);
  
  console.log(`[BLV Drift] Checking ${baselines.length} branch baselines...`);
  
  for (const baseline of baselines) {
    try {
      await detectBaselineDrift(baseline.branchId, baseline.timeSlot);
    } catch (error: any) {
      console.error(`[BLV Drift] Error checking branch ${baseline.branchId}:`, error.message);
    }
  }
  
  console.log('[BLV Drift] Drift detection complete');
}
