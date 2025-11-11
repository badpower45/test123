/**
 * BLV (Behavioral Location Verification) Service
 * 
 * This service calculates presence and trust scores based on environmental signals
 * collected from the employee's device and compares them against branch baselines.
 */

import { db } from '../db.js';
import { 
  branchEnvironmentBaselines, 
  deviceCalibrations, 
  employeeDeviceBaselines,
  blvSystemConfig,
  pulseFlags
} from '../../shared/schema.js';
import { eq, and } from 'drizzle-orm';

// ============================================================================
// TYPES & INTERFACES
// ============================================================================

export interface EnvironmentalData {
  wifiCount: number;
  wifiSignalStrength: number;
  batteryLevel: number;
  isCharging: boolean;
  accelVariance: number;
  soundLevel: number;
  deviceOrientation?: string;
  deviceModel: string;
  osVersion: string;
}

export interface BLVVerificationResult {
  presenceScore: number;      // 0.0 to 1.0
  trustScore: number;          // 0.0 to 1.0
  isValid: boolean;            // true if scores pass thresholds
  verificationMethod: string;  // 'BLV', 'WiFi', 'Hybrid', 'Manual'
  status: string;              // 'IN', 'SUSPECT', 'REVIEW_REQUIRED'
  flags: string[];             // Array of detected issues
  details: {
    wifiScore: number;
    motionScore: number;
    soundScore: number;
    batteryScore: number;
    baselineConfidence: number;
  };
}

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/**
 * Get time slot based on hour of day
 */
function getTimeSlot(date: Date): string {
  const hour = date.getHours();
  if (hour >= 6 && hour < 12) return 'morning';
  if (hour >= 12 && hour < 18) return 'afternoon';
  if (hour >= 18 && hour < 22) return 'evening';
  return 'night';
}

/**
 * Normalize sensor reading based on device calibration
 */
function normalizeReading(
  value: number, 
  calibrationFactor: number, 
  readingType: 'accel' | 'sound' | 'wifi'
): number {
  return value * calibrationFactor;
}

/**
 * Calculate similarity score between two values with tolerance
 */
function calculateSimilarityScore(
  actual: number,
  expected: number,
  stdDev: number,
  tolerance: number = 2.0
): number {
  if (stdDev === 0 || stdDev === null || stdDev === undefined) {
    // If no standard deviation, use simple percentage difference
    const diff = Math.abs(actual - expected);
    const avgValue = (Math.abs(actual) + Math.abs(expected)) / 2;
    if (avgValue === 0) return 1.0;
    const percentDiff = diff / avgValue;
    return Math.max(0, 1 - percentDiff);
  }

  // Calculate Z-score (how many standard deviations away)
  const zScore = Math.abs((actual - expected) / stdDev);
  
  // If within tolerance * stdDev, calculate score
  if (zScore <= tolerance) {
    return 1 - (zScore / tolerance);
  }
  
  return 0;
}

/**
 * Calculate range-based score (checks if value is within expected range)
 */
function calculateRangeScore(
  actual: number,
  min: number,
  max: number,
  tolerance: number = 0.2
): number {
  // Add tolerance margin
  const range = max - min;
  const toleranceMargin = range * tolerance;
  const adjustedMin = min - toleranceMargin;
  const adjustedMax = max + toleranceMargin;

  if (actual >= adjustedMin && actual <= adjustedMax) {
    // Within range, calculate how centered it is
    const center = (min + max) / 2;
    const distanceFromCenter = Math.abs(actual - center);
    const maxDistance = range / 2;
    return 1 - (distanceFromCenter / maxDistance) * 0.3; // Max penalty 30%
  }

  // Outside range
  const distanceOutside = actual < adjustedMin 
    ? adjustedMin - actual 
    : actual - adjustedMax;
  
  // Exponential decay for values outside range
  return Math.max(0, Math.exp(-distanceOutside / range));
}

// ============================================================================
// MAIN VERIFICATION FUNCTIONS
// ============================================================================

/**
 * Verify employee presence using BLV (Behavioral Location Verification)
 */
export async function verifyPresence(
  employeeId: string,
  branchId: string,
  environmentalData: EnvironmentalData,
  bssidAddress?: string
): Promise<BLVVerificationResult> {
  
  try {
    // 1. Get configuration
    const config = await getConfig(branchId);
    
    // 2. Get device calibration
    const calibration = await getDeviceCalibration(environmentalData.deviceModel);
    
    // 3. Normalize sensor readings
    const normalizedData = normalizeEnvironmentalData(environmentalData, calibration);
    
    // 4. Get branch baseline for current time
    const timeSlot = getTimeSlot(new Date());
    const baseline = await getBranchBaseline(branchId, timeSlot);
    
    // 5. Get employee personal baseline (if exists)
    const employeeBaseline = await getEmployeeBaseline(employeeId, environmentalData.deviceModel);
    
    // 6. Calculate individual component scores
    const wifiScore = calculateWifiScore(normalizedData, baseline, config);
    const motionScore = calculateMotionScore(normalizedData, baseline, employeeBaseline, config);
    const soundScore = calculateSoundScore(normalizedData, baseline, config);
    const batteryScore = calculateBatteryScore(normalizedData, baseline, config);
    
    // 7. Calculate weighted presence score
    const presenceScore = (
      wifiScore * config.wifiWeight +
      motionScore * config.motionWeight +
      soundScore * config.soundWeight +
      batteryScore * config.batteryWeight
    );
    
    // 8. Calculate trust score (fraud detection)
    const trustAnalysis = calculateTrustScore(normalizedData, baseline, employeeBaseline);
    const trustScore = trustAnalysis.score;
    const flags = trustAnalysis.flags;
    
    // 9. Determine if valid
    const isValid = presenceScore >= config.minPresenceScore && 
                    trustScore >= config.minTrustScore;
    
    // 10. Determine status
    let status = 'IN';
    if (!isValid) {
      status = trustScore < config.minTrustScore ? 'SUSPECT' : 'REVIEW_REQUIRED';
    }
    
    // 11. Determine verification method
    let verificationMethod = 'BLV';
    if (config.fallbackToWifiOnly && baseline.confidence < 0.5) {
      verificationMethod = 'WiFi';
      // If WiFi BSSID provided and matches, override to valid
      if (bssidAddress) {
        // This will be checked separately in the main pulse endpoint
        verificationMethod = 'WiFi';
      }
    }
    
    return {
      presenceScore,
      trustScore,
      isValid,
      verificationMethod,
      status,
      flags,
      details: {
        wifiScore,
        motionScore,
        soundScore,
        batteryScore,
        baselineConfidence: baseline.confidence
      }
    };
    
  } catch (error) {
    console.error('[BLV] Verification error:', error);
    
    // Fallback to WiFi-only in case of errors
    return {
      presenceScore: 0.5,
      trustScore: 0.5,
      isValid: false,
      verificationMethod: 'WiFi',
      status: 'REVIEW_REQUIRED',
      flags: ['BLV_ERROR'],
      details: {
        wifiScore: 0,
        motionScore: 0,
        soundScore: 0,
        batteryScore: 0,
        baselineConfidence: 0
      }
    };
  }
}

// ============================================================================
// SCORE CALCULATION FUNCTIONS
// ============================================================================

function calculateWifiScore(
  data: EnvironmentalData,
  baseline: any,
  config: any
): number {
  if (!baseline.avgWifiCount) return 0.5; // No baseline data
  
  // Score based on WiFi count similarity
  const countScore = calculateSimilarityScore(
    data.wifiCount,
    baseline.avgWifiCount,
    baseline.wifiCountStdDev || 2,
    2.0
  );
  
  // Score based on signal strength (if available)
  let signalScore = 0.5; // Default
  if (data.wifiSignalStrength && baseline.avgSignalStrength) {
    signalScore = calculateSimilarityScore(
      data.wifiSignalStrength,
      baseline.avgSignalStrength,
      10, // ±10 dBm tolerance
      2.0
    );
  }
  
  // Weighted combination
  return countScore * 0.7 + signalScore * 0.3;
}

function calculateMotionScore(
  data: EnvironmentalData,
  baseline: any,
  employeeBaseline: any,
  config: any
): number {
  // Use employee personal baseline if available, otherwise branch baseline
  const expectedVariance = employeeBaseline?.personalAccelVariance || baseline.avgAccelVariance;
  const stdDev = baseline.accelVarianceStdDev || 0.01;
  
  if (!expectedVariance) return 0.5; // No baseline
  
  return calculateSimilarityScore(
    data.accelVariance,
    expectedVariance,
    stdDev,
    2.5 // More tolerance for motion
  );
}

function calculateSoundScore(
  data: EnvironmentalData,
  baseline: any,
  config: any
): number {
  if (!baseline.avgSoundLevel) return 0.5; // No baseline
  
  return calculateSimilarityScore(
    data.soundLevel,
    baseline.avgSoundLevel,
    baseline.soundLevelStdDev || 0.1,
    2.0
  );
}

function calculateBatteryScore(
  data: EnvironmentalData,
  baseline: any,
  config: any
): number {
  if (!baseline.avgBatteryLevel) return 0.5; // No baseline
  
  // Battery level score
  const levelScore = calculateSimilarityScore(
    data.batteryLevel,
    baseline.avgBatteryLevel,
    0.2, // ±20% tolerance
    2.0
  );
  
  // Charging pattern score
  let chargingScore = 0.5;
  if (baseline.chargingLikelihood !== null && baseline.chargingLikelihood !== undefined) {
    const expectedCharging = baseline.chargingLikelihood > 0.5;
    const actualCharging = data.isCharging;
    chargingScore = expectedCharging === actualCharging ? 1.0 : 0.3;
  }
  
  return levelScore * 0.6 + chargingScore * 0.4;
}

// ============================================================================
// TRUST SCORE & FRAUD DETECTION
// ============================================================================

function calculateTrustScore(
  data: EnvironmentalData,
  baseline: any,
  employeeBaseline: any
): { score: number; flags: string[] } {
  
  let trustScore = 1.0;
  const flags: string[] = [];
  
  // 1. No Motion Detection (device left stationary)
  if (data.accelVariance < 0.001) {
    trustScore *= 0.7;
    flags.push('NO_MOTION');
  }
  
  // 2. Passive Audio (constant sound level - suspicious)
  if (data.soundLevel < 0.01 || (baseline.avgSoundLevel > 0.1 && data.soundLevel < 0.01)) {
    trustScore *= 0.8;
    flags.push('PASSIVE_AUDIO');
  }
  
  // 3. Anomalous WiFi count (too many or too few)
  if (baseline.avgWifiCount) {
    const wifiDiff = Math.abs(data.wifiCount - baseline.avgWifiCount);
    if (wifiDiff > 10) {
      trustScore *= 0.6;
      flags.push('ANOMALOUS_WIFI');
    }
  }
  
  // 4. Battery pattern anomaly
  if (data.batteryLevel === 1.0 && data.isCharging) {
    // Fully charged and still charging - normal
  } else if (!data.isCharging && data.batteryLevel > 0.95) {
    // Suspiciously high battery without charging
    trustScore *= 0.9;
    flags.push('BATTERY_ANOMALY');
  }
  
  // 5. Unrealistic values
  if (data.wifiCount > 50) {
    trustScore *= 0.5;
    flags.push('WIFI_COUNT_UNREALISTIC');
  }
  
  if (data.accelVariance > 1.0) {
    trustScore *= 0.7;
    flags.push('MOTION_UNREALISTIC');
  }
  
  return { score: Math.max(0, trustScore), flags };
}

// ============================================================================
// DATABASE HELPER FUNCTIONS
// ============================================================================

async function getConfig(branchId: string): Promise<any> {
  // Try to get branch-specific config first
  const branchConfig = await db
    .select()
    .from(blvSystemConfig)
    .where(and(
      eq(blvSystemConfig.branchId, branchId),
      eq(blvSystemConfig.isActive, true)
    ))
    .limit(1);
  
  if (branchConfig.length > 0) {
    return branchConfig[0];
  }
  
  // Fall back to global config
  const globalConfig = await db
    .select()
    .from(blvSystemConfig)
    .where(and(
      eq(blvSystemConfig.branchId, null),
      eq(blvSystemConfig.isActive, true)
    ))
    .limit(1);
  
  if (globalConfig.length > 0) {
    return globalConfig[0];
  }
  
  // Return default config
  return {
    minPresenceScore: 0.7,
    minTrustScore: 0.6,
    wifiWeight: 0.4,
    motionWeight: 0.2,
    soundWeight: 0.2,
    batteryWeight: 0.2,
    fallbackToWifiOnly: true,
    allowManualOverride: true
  };
}

async function getDeviceCalibration(deviceModel: string): Promise<any> {
  const calibrations = await db
    .select()
    .from(deviceCalibrations)
    .where(eq(deviceCalibrations.deviceModel, deviceModel))
    .limit(1);
  
  if (calibrations.length > 0) {
    return calibrations[0];
  }
  
  // Return default calibration
  return {
    accelCalibrationFactor: 1.0,
    soundCalibrationFactor: 1.0,
    wifiSignalCalibrationFactor: 1.0
  };
}

function normalizeEnvironmentalData(
  data: EnvironmentalData,
  calibration: any
): EnvironmentalData {
  return {
    ...data,
    accelVariance: normalizeReading(data.accelVariance, calibration.accelCalibrationFactor, 'accel'),
    soundLevel: normalizeReading(data.soundLevel, calibration.soundCalibrationFactor, 'sound'),
    wifiSignalStrength: normalizeReading(data.wifiSignalStrength, calibration.wifiSignalCalibrationFactor, 'wifi')
  };
}

async function getBranchBaseline(branchId: string, timeSlot: string): Promise<any> {
  const baselines = await db
    .select()
    .from(branchEnvironmentBaselines)
    .where(and(
      eq(branchEnvironmentBaselines.branchId, branchId),
      eq(branchEnvironmentBaselines.timeSlot, timeSlot)
    ))
    .limit(1);
  
  if (baselines.length > 0) {
    return baselines[0];
  }
  
  // Return empty baseline with low confidence
  return {
    avgWifiCount: null,
    wifiCountStdDev: null,
    avgSignalStrength: null,
    avgBatteryLevel: null,
    chargingLikelihood: null,
    avgAccelVariance: null,
    accelVarianceStdDev: null,
    avgSoundLevel: null,
    soundLevelStdDev: null,
    confidence: 0
  };
}

async function getEmployeeBaseline(employeeId: string, deviceModel: string): Promise<any> {
  const baselines = await db
    .select()
    .from(employeeDeviceBaselines)
    .where(and(
      eq(employeeDeviceBaselines.employeeId, employeeId),
      eq(employeeDeviceBaselines.deviceModel, deviceModel)
    ))
    .limit(1);
  
  if (baselines.length > 0) {
    return baselines[0];
  }
  
  return null;
}

// ============================================================================
// AUTO-FLAG CREATION
// ============================================================================

export async function createAutoFlags(
  pulseId: string,
  employeeId: string,
  flags: string[],
  verificationResult: BLVVerificationResult
): Promise<void> {
  
  for (const flagType of flags) {
    let severity = 'medium';
    let description = '';
    
    switch (flagType) {
      case 'NO_MOTION':
        severity = 'high';
        description = 'الجهاز ثابت تماماً (لا حركة) - احتمال ترك الجهاز';
        break;
      case 'PASSIVE_AUDIO':
        severity = 'medium';
        description = 'مستوى الصوت ثابت أو منخفض جداً';
        break;
      case 'ANOMALOUS_WIFI':
        severity = 'high';
        description = 'عدد شبكات WiFi غير طبيعي';
        break;
      case 'BATTERY_ANOMALY':
        severity = 'low';
        description = 'نمط البطارية غير معتاد';
        break;
      case 'WIFI_COUNT_UNREALISTIC':
        severity = 'critical';
        description = 'عدد شبكات WiFi غير منطقي (محتمل تزوير)';
        break;
      case 'MOTION_UNREALISTIC':
        severity = 'critical';
        description = 'قيم الحركة غير منطقية (محتمل تزوير)';
        break;
      case 'BLV_ERROR':
        severity = 'low';
        description = 'خطأ في نظام BLV - تم التحقق بـ WiFi فقط';
        break;
    }
    
    try {
      await db.insert(pulseFlags).values({
        pulseId,
        employeeId,
        flagType,
        severity,
        description,
        details: JSON.stringify(verificationResult),
        isResolved: false
      });
    } catch (error) {
      console.error('[BLV] Failed to create auto-flag:', error);
    }
  }
}
