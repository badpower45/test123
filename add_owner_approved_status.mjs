import { neon } from '@neondatabase/serverless';
import dotenv from 'dotenv';

dotenv.config();
const sql = neon(process.env.DATABASE_URL);

async function addOwnerApprovedStatus() {
  try {
    console.log('Adding owner_approved status to request_status enum...\n');

    // Add owner_approved to the enum
    await sql`
      ALTER TYPE request_status ADD VALUE IF NOT EXISTS 'owner_approved'
    `;

    console.log('✅ Successfully added owner_approved status to request_status enum!');
  } catch (error) {
    console.error('❌ Error adding owner_approved status:', error);
    process.exit(1);
  }
}

addOwnerApprovedStatus();
