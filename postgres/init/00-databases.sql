-- One database and one login per service. No service reads another service's tables.
-- Local development passwords only; real environments take them from secrets.
--
-- Safe to run again: PostgreSQL runs it on the first start of an empty volume, and
-- scripts/up.sh runs it on every start, so a service added later gets its database on a
-- stack that already has data.

SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', name, name)
FROM unnest(ARRAY['likho_api', 'likho_media', 'likho_language', 'likho_connector', 'likho_ml']) AS name
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = name)
\gexec

SELECT format('CREATE DATABASE %I OWNER %I', name, name)
FROM unnest(ARRAY['likho_api', 'likho_media', 'likho_language', 'likho_connector', 'likho_ml']) AS name
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = name)
\gexec

SELECT format('REVOKE CONNECT ON DATABASE %I FROM PUBLIC', name)
FROM unnest(ARRAY['likho_api', 'likho_media', 'likho_language', 'likho_connector', 'likho_ml']) AS name
\gexec
