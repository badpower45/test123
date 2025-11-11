/**
 * Baseline Calculation Service
 * 
 * This service calculates and updates environmental baselines for branches.
 * It analyzes historical pulse data to create "fingerprints" for each branch
 * at different times of day.
 */

import { db } from '../db.js';
import { 
  pulses,
  branchEnvironmentBaselines,
  employeeDeviceBaselines,
  blvSystemConfig
} from '../../shared/schema.js';
import { eq, and, gte, lte, sql, isNotNull } from 'drizzle-orm';

// ============================================================================
// CONFIDENCE DECAY SYSTEM
// ============================================================================

/**
 * Calculate baseline confidence with decay factor
 * Confidence decays over time to account for environmental changes
 * Formula: confidence * (0.98 ^ days_since_update)
 */
export function calculateBaselineConfidence(
  baselineConfidence: number,
  lastUpdated: Date,
  currentDate: Date = new Date()
): number {
  const daysSinceUpdate = Math.floor(
    (currentDate.getTime() - lastUpdated.getTime()) / (1000 * 60 * 60 * 24)
  );
  
  // Decay factor: 0.98 ^ days
  // After 30 days: 0.98^30 = 0.545 (54.5%)
  // After 60 days: 0.98^60 = 0.297 (29.7%)
  const decayFactor = Math.pow(0.98, daysSinceUpdate);
  
  const decayedConfidence = baselineConfidence * decayFactor;
  
  console.log(`[BLV Decay] Days: ${daysSinceUpdate}, Decay: ${decayFactor.toFixed(3)}, Confidence: ${baselineConfidence.toFixed(2)} → ${decayedConfidence.toFixed(2)}`);
  
  return decayedConfidence;
}

/**
 * Check if baseline needs recalculation
 */
export function shouldRecalibrateBaseline(
  baselineConfidence: number,
  lastUpdated: Date,
  threshold: number = 0.5
): boolean {
  const currentConfidence = calculateBaselineConfidence(
    baselineConfidence,
    lastUpdated
  );
  
  return currentConfidence < threshold;
}

// ============================================================================
// BASELINE CALCULATION
// ============================================================================

/**
 * Calculate and update branch baseline for a specific time slot
 */
export async function calculateBranchBaseline(
  branchId: string,
  timeSlot: string,
  startDate: Date,
  endDate: Date
): Promise<void> {
  
  console.log(`[BLV] Calculating baseline for branch ${branchId}, time slot: ${timeSlot}`);
  
  // Get all pulses for this branch and time slot
  const pulsesData = await db
    .select({
      wifiCount: pulses.wifiCount,
      wifiSignalStrength: pulses.wifiSignalStrength,
      batteryLevel: pulses.batteryLevel,
      isCharging: pulses.isCharging,
      accelVariance: pulses.accelVariance,
      soundLevel: pulses.soundLevel,
      timestamp: pulses.timestamp
    })
    .from(pulses)
    .where(and(
      eq(pulses.branchId, branchId),
      gte(pulses.timestamp, startDate),
      lte(pulses.timestamp, endDate),
      isNotNull(pulses.wifiCount),
      isNotNull(pulses.accelVariance)
    ));
  
  // Filter by time slot
  const filteredPulses = pulsesData.filter(p => {
    const hour = new Date(p.timestamp).getHours();
    return getTimeSlotForHour(hour) === timeSlot;
  });
  
  if (filteredPulses.length < 10) {
    console.log(`[BLV] Not enough samples (${filteredPulses.length}) for baseline calculation`);
    return;
  }
  
  console.log(`[BLV] Analyzing ${filteredPulses.length} samples...`);
  
  // Calculate statistics
  const stats = calculateStatistics(filteredPulses);
  
  // Calculate confidence based on sample count
  const minSamples = 50;
  const confidence = Math.min(1.0, filteredPulses.length / minSamples);
  
  // Check if baseline exists
  const existing = await db
    .select()
    .from(branchEnvironmentBaselines)
    .where(and(
      eq(branchEnvironmentBaselines.branchId, branchId),
      eq(branchEnvironmentBaselines.timeSlot, timeSlot)
    ))
    .limit(1);
  
  if (existing.length > 0) {
    // Update existing baseline (moving average)
    const oldBaseline = existing[0];
    const alpha = 0.3; // Weight for new data (30% new, 70% old)
    
    await db
      .update(branchEnvironmentBaselines)
      .set({
        avgWifiCount: blend(oldBaseline.avgWifiCount, stats.avgWifiCount, alpha),
        wifiCountStdDev: blend(oldBaseline.wifiCountStdDev, stats.wifiCountStdDev, alpha),
        avgSignalStrength: blend(oldBaseline.avgSignalStrength, stats.avgSignalStrength, alpha),
        avgBatteryLevel: blend(oldBaseline.avgBatteryLevel, stats.avgBatteryLevel, alpha),
        chargingLikelihood: blend(oldBaseline.chargingLikelihood, stats.chargingLikelihood, alpha),
        avgAccelVariance: blend(oldBaseline.avgAccelVariance, stats.avgAccelVariance, alpha),
        accelVarianceStdDev: blend(oldBaseline.accelVarianceStdDev, stats.accelVarianceStdDev, alpha),
        avgSoundLevel: blend(oldBaseline.avgSoundLevel, stats.avgSoundLevel, alpha),
        soundLevelStdDev: blend(oldBaseline.soundLevelStdDev, stats.soundLevelStdDev, alpha),
        sampleCount: (oldBaseline.sampleCount || 0) + filteredPulses.length,
        confidence,
        lastUpdated: new Date(),
        updatedAt: new Date()
      })
      .where(eq(branchEnvironmentBaselines.id, oldBaseline.id));
    
    console.log(`[BLV] Updated baseline for ${timeSlot} (${filteredPulses.length} new samples)`);
    
  } else {
    // Create new baseline
    await db
      .insert(branchEnvironmentBaselines)
      .values({
        branchId,
        timeSlot,
        avgWifiCount: stats.avgWifiCount,
        wifiCountStdDev: stats.wifiCountStdDev,
        avgSignalStrength: stats.avgSignalStrength,
        avgBatteryLevel: stats.avgBatteryLevel,
        chargingLikelihood: stats.chargingLikelihood,
        avgAccelVariance: stats.avgAccelVariance,
        accelVarianceStdDev: stats.accelVarianceStdDev,
        avgSoundLevel: stats.avgSoundLevel,
        soundLevelStdDev: stats.soundLevelStdDev,
        sampleCount: filteredPulses.length,
        confidence,
        lastUpdated: new Date()
      });
    
    console.log(`[BLV] Created new baseline for ${timeSlot} (${filteredPulses.length} samples)`);
  }
}

/**
 * Calculate baselines for all time slots for a branch
 */
export async function calculateAllBaselines(
  branchId: string,
  daysBack: number = 14
): Promise<void> {
  
  const endDate = new Date();
  const startDate = new Date();
  startDate.setDate(startDate.getDate() - daysBack);
  
  const timeSlots = ['morning', 'afternoon', 'evening', 'night'];
  
  for (const timeSlot of timeSlots) {
    await calculateBranchBaseline(branchId, timeSlot, startDate, endDate);
  }
}

/**
 * Calculate employee-device personal baseline
 */
export async function calculateEmployeeBaseline(
  employeeId: string,
  deviceId: string,
  deviceModel: string,
  daysBack: number = 30
): Promise<void> {
  
  console.log(`[BLV] Calculating employee baseline for ${employeeId} on ${deviceModel}`);
  
  const endDate = new Date();
  const startDate = new Date();
  startDate.setDate(startDate.getDate() - daysBack);
  
  // Get employee's pulses
  const pulsesData = await db
    .select({
      accelVariance: pulses.accelVariance,
      soundLevel: pulses.soundLevel,
      presenceScore: pulses.presenceScore
    })
    .from(pulses)
    .where(and(
      eq(pulses.employeeId, employeeId),
      gte(pulses.timestamp, startDate),
      lte(pulses.timestamp, endDate),
      isNotNull(pulses.accelVariance),
      eq(pulses.deviceModel, deviceModel)
    ));
  
  if (pulsesData.length < 20) {
    console.log(`[BLV] Not enough samples for employee baseline`);
    return;
  }
  
  // Calculate personal patterns
  const avgAccelVariance = average(pulsesData.map(p => p.accelVariance).filter(v => v !== null));
  const avgSoundLevel = average(pulsesData.map(p => p.soundLevel).filter(v => v !== null));
  const avgPresenceScore = average(pulsesData.map(p => p.presenceScore).filter(v => v !== null));
  
  // Check if baseline exists
  const existing = await db
    .select()
    .from(employeeDeviceBaselines)
    .where(and(
      eq(employeeDeviceBaselines.employeeId, employeeId),
      eq(employeeDeviceBaselines.deviceId, deviceId)
    ))
    .limit(1);
  
  if (existing.length > 0) {
    // Update
    await db
      .update(employeeDeviceBaselines)
      .set({
        personalAccelVariance: avgAccelVariance,
        personalSoundSensitivity: avgSoundLevel,
        totalPulses: (existing[0].totalPulses || 0) + pulsesData.length,
        avgPresenceScore,
        updatedAt: new Date()
      })
      .where(eq(employeeDeviceBaselines.id, existing[0].id));
    
  } else {
    // Create
    await db
      .insert(employeeDeviceBaselines)
      .values({
        employeeId,
        deviceId,
        deviceModel,
        personalAccelVariance: avgAccelVariance,
        personalSoundSensitivity: avgSoundLevel,
        totalPulses: pulsesData.length,
        avgPresenceScore
      });
  }
  
  console.log(`[BLV] Employee baseline updated (${pulsesData.length} samples)`);
}

// ============================================================================
// STATISTICS HELPERS
// ============================================================================

function calculateStatistics(pulses: any[]): any {
  return {
    avgWifiCount: average(pulses.map(p => p.wifiCount).filter(v => v !== null)),
    wifiCountStdDev: standardDeviation(pulses.map(p => p.wifiCount).filter(v => v !== null)),
    avgSignalStrength: average(pulses.map(p => p.wifiSignalStrength).filter(v => v !== null)),
    avgBatteryLevel: average(pulses.map(p => p.batteryLevel).filter(v => v !== null)),
    chargingLikelihood: pulses.filter(p => p.isCharging).length / pulses.length,
    avgAccelVariance: average(pulses.map(p => p.accelVariance).filter(v => v !== null)),
    accelVarianceStdDev: standardDeviation(pulses.map(p => p.accelVariance).filter(v => v !== null)),
    avgSoundLevel: average(pulses.map(p => p.soundLevel).filter(v => v !== null)),
    soundLevelStdDev: standardDeviation(pulses.map(p => p.soundLevel).filter(v => v !== null))
  };
}

function average(values: number[]): number | null {
  if (values.length === 0) return null;
  return values.reduce((sum, val) => sum + val, 0) / values.length;
}

function standardDeviation(values: number[]): number | null {
  if (values.length < 2) return null;
  const avg = average(values);
  if (avg === null) return null;
  const squareDiffs = values.map(value => Math.pow(value - avg, 2));
  const avgSquareDiff = average(squareDiffs);
  if (avgSquareDiff === null) return null;
  return Math.sqrt(avgSquareDiff);
}

function blend(oldValue: number | null, newValue: number | null, alpha: number): number | null {
  if (oldValue === null) return newValue;
  if (newValue === null) return oldValue;
  return oldValue * (1 - alpha) + newValue * alpha;
}

function getTimeSlotForHour(hour: number): string {
  if (hour >= 6 && hour < 12) return 'morning';
  if (hour >= 12 && hour < 18) return 'afternoon';
  if (hour >= 18 && hour < 22) return 'evening';
  return 'night';
}

// ============================================================================
// SCHEDULED BASELINE UPDATES
// ============================================================================

/**
 * Update all branch baselines (should be run weekly via cron)
 */
export async function updateAllBranchBaselines(): Promise<void> {
  console.log('[BLV] Starting scheduled baseline update for all branches...');
  
  try {
    // Get all unique branch IDs from pulses
    const branchesResult = await db
      .selectDistinct({ branchId: pulses.branchId })
      .from(pulses)
      .where(isNotNull(pulses.branchId));
    
    const branchIds = branchesResult.map(b => b.branchId).filter(id => id !== null);
    
    console.log(`[BLV] Found ${branchIds.length} branches to update`);
    
    for (const branchId of branchIds) {
      try {
        await calculateAllBaselines(branchId!, 14); // Use last 14 days
      } catch (error) {
        console.error(`[BLV] Failed to update baseline for branch ${branchId}:`, error);
      }
    }
    
    console.log('[BLV] Baseline update completed');
    
  } catch (error) {
    console.error('[BLV] Baseline update failed:', error);
  }
}
