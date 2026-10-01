-- One database and one login per service. No service reads another service's tables.
-- Local development passwords only; real environments take them from secrets.
CREATE ROLE likho_api      LOGIN PASSWORD 'likho_api';
CREATE ROLE likho_media    LOGIN PASSWORD 'likho_media';
CREATE ROLE likho_language LOGIN PASSWORD 'likho_language';

CREATE DATABASE likho_api      OWNER likho_api;
CREATE DATABASE likho_media    OWNER likho_media;
CREATE DATABASE likho_language OWNER likho_language;

REVOKE CONNECT ON DATABASE likho_api      FROM PUBLIC;
REVOKE CONNECT ON DATABASE likho_media    FROM PUBLIC;
REVOKE CONNECT ON DATABASE likho_language FROM PUBLIC;
