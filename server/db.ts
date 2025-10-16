import { Pool, neonConfig } from '@neondatabase/serverless';
import { drizzle } from 'drizzle-orm/neon-serverless';
import ws from "ws";
import * as schema from "@shared/schema";

neonConfig.webSocketConstructor = ws;

const DEFAULT_DATABASE_URL = 'postgresql://postgres:password@db.local:5432/postgres';
const connectionString = process.env.DATABASE_URL?.trim() || DEFAULT_DATABASE_URL;

if (!process.env.DATABASE_URL) {
  console.warn('[db] DATABASE_URL not set. Falling back to local development connection string.');
}

export const pool = new Pool({ connectionString });
export const db = drizzle({ client: pool, schema });
