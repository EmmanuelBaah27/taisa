import Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';

const DB_PATH = process.env.DB_PATH || path.join(__dirname, '../../taisa.db');

let db: Database.Database;

export function getDb(): Database.Database {
  if (!db) {
    db = new Database(DB_PATH);
    db.pragma('journal_mode = WAL');
    db.pragma('foreign_keys = ON');
    initSchema();
  }
  return db;
}

function initSchema(): void {
  const schemaPath = path.join(__dirname, 'schema.sql');
  const schema = fs.readFileSync(schemaPath, 'utf-8');
  db.exec(schema);
  runMigrations();
}

function runMigrations(): void {
  const cols = (db.prepare('PRAGMA table_info(chat_sessions)').all() as any[]).map(c => c.name);
  if (!cols.includes('title')) {
    db.exec('ALTER TABLE chat_sessions ADD COLUMN title TEXT');
  }
  if (!cols.includes('last_message_at')) {
    db.exec('ALTER TABLE chat_sessions ADD COLUMN last_message_at TEXT');
  }
}

export default getDb;
