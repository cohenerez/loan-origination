-- Runs once, when the PostgreSQL volume is first created. One database per service.
-- scoring is already created by POSTGRES_DB; each line is safe to re-run.
SELECT 'CREATE DATABASE scoring'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'scoring')\gexec
SELECT 'CREATE DATABASE notifications'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'notifications')\gexec
SELECT 'CREATE DATABASE bridge'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'bridge')\gexec