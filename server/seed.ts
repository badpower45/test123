import { db } from './db.js';
import { employees, attendance, pulses } from '../shared/schema.js';

async function seedHistoricalData() {
  try {
    console.log('🌱 Seeding historical data...');

    const today = new Date();
    today.setHours(0, 0, 0, 0);

    // Seed attendance for the last 7 days
    const attendanceRecords = [];
    for (let i = 7; i >= 1; i--) {
      const date = new Date(today);
      date.setDate(date.getDate() - i);
      
      const checkInTime = new Date(date);
      checkInTime.setHours(8 + Math.floor(Math.random() * 2), Math.floor(Math.random() * 30), 0);
      
      const checkOutTime = new Date(date);
      checkOutTime.setHours(16 + Math.floor(Math.random() * 2), Math.floor(Math.random() * 30), 0);
      
      const workHours = ((checkOutTime.getTime() - checkInTime.getTime()) / (1000 * 60 * 60)).toFixed(2);

      attendanceRecords.push({
        employeeId: 'rr',
        checkInTime,
        checkOutTime,
        workHours,
        date: date.toISOString().split('T')[0],
        status: 'completed',
        isAutoCheckout: false,
      });
    }

    await db.insert(attendance).values(attendanceRecords).onConflictDoNothing();
    console.log(`✅ Added ${attendanceRecords.length} attendance records`);

    // Seed some pulses for today
    const pulseRecords = [];
    const now = new Date();
    for (let i = 0; i < 10; i++) {
      const pulseTime = new Date(now.getTime() - (i * 5 * 60 * 1000)); // Every 5 minutes
      pulseRecords.push({
        employeeId: 'rr',
        timestamp: pulseTime,
        latitude: 30.0444 + (Math.random() - 0.5) * 0.001,
        longitude: 31.2357 + (Math.random() - 0.5) * 0.001,
        isWithinGeofence: true,
        sentFromDevice: true,
      });
    }

    await db.insert(pulses).values(pulseRecords).onConflictDoNothing();
    console.log(`✅ Added ${pulseRecords.length} pulse records`);

    console.log('🎉 Seeding complete!');
    process.exit(0);
  } catch (error) {
    console.error('❌ Seeding failed:', error);
    process.exit(1);
  }
}

seedHistoricalData();
