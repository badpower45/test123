import { drizzle } from 'drizzle-orm/node-postgres';
import { eq } from 'drizzle-orm';
import pg from 'pg';
import * as schema from './dist/shared/schema.js';

const { Pool } = pg;
const pool = new Pool({ connectionString: process.env.DATABASE_URL });
const db = drizzle(pool, { schema });

(async () => {
  try {
    await db.update(schema.employees)
      .set({ pinHash: '9999' })
      .where(eq(schema.employees.id, 'MGR001'));
    console.log('✓ Updated MGR001 PIN to 9999');
    process.exit(0);
  } catch (error) {
    console.error('Error:', error);
    process.exit(1);
  }
})();
