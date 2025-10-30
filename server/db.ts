import { Pool, neonConfig } from '@neondatabase/serverless';
import { drizzle } from 'drizzle-orm/neon-serverless';
import { sql } from 'drizzle-orm';
import { config as loadEnv } from 'dotenv';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import ws from 'ws';
import * as schema from '../shared/schema';

neonConfig.webSocketConstructor = ws;

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const envCandidates = [
  path.resolve(process.cwd(), '.env.local'),
  path.resolve(process.cwd(), '.env'),
  path.resolve(__dirname, '.env'),
  path.resolve(__dirname, '../.env'),
];

const loadedEnvPaths: string[] = [];

for (const envPath of envCandidates) {
  if (fs.existsSync(envPath)) {
    loadEnv({ path: envPath, override: true });
    loadedEnvPaths.push(envPath);
  }
}

if (loadedEnvPaths.length > 0) {
  console.log('[db] Loaded env files:', loadedEnvPaths.join(', '));
} else {
  console.warn('[db] No .env files found in expected locations.');
}

if (process.env.DATABASE_URL) {
  console.log('[db] DATABASE_URL detected (length:', process.env.DATABASE_URL!.length, ')');
}

const DEFAULT_DATABASE_URL = 'postgresql://postgres:password@db.local:5432/postgres';
const connectionString = process.env.DATABASE_URL?.trim() || DEFAULT_DATABASE_URL;

if (!process.env.DATABASE_URL) {
  console.warn('[db] DATABASE_URL not set. Falling back to local development connection string.');
}

export const pool = new Pool({ connectionString });

// Add connection logging
pool.on('connect', (client) => {
  console.log('[db] New client connected to database');
});

pool.on('error', (err, client) => {
  console.error('[db] Database connection error:', err);
});

export const db = drizzle({ client: pool, schema });

// Test connection
db.execute(sql`SELECT 1`).then(() => {
  console.log('[db] Database connection test successful');
}).catch(err => {
  console.error('[db] Database connection test failed:', err);
});
