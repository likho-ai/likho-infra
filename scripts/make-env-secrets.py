"""Makes the secret .env.<environment>.local files of every service, with fresh random values.

    python scripts/make-env-secrets.py staging
    python scripts/make-env-secrets.py production --force     # replace existing files

Writes, next to this repository (the D:\\likho layout):

    likho-infra/.env.<env>.local            every secret of the environment (the source)
    likho-language/.env.<env>.local         DATABASE_URL
    likho-media/.env.<env>.local            DATABASE_URL, S3 keys, LINK_SECRET, PUBLIC_URL
    likho-transcription/.env.<env>.local    MONGO_URL
    likho-api/.env.<env>.local              DATABASE_URL, SESSION_SECRET, the first admin, PUBLIC_ORIGIN
    likho-search/.env.<env>.local           MEILI_API_KEY
    likho-connector-ameyo/.env.<env>.local  DATABASE_URL, and placeholders for the API key and the dialer

The files are ignored by git. likho-deploy turns them into Kubernetes Secrets (scripts/secrets.py
there); its stack chart creates the database users with these passwords on first start. Two values cannot be invented and are
left for you to fill: the public domain (PUBLIC_URL / PUBLIC_ORIGIN) and the first admin's email.
"""

import secrets
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ENVIRONMENTS = ("staging", "production")


def token(length: int = 32) -> str:
    return secrets.token_urlsafe(length)


def main() -> int:
    if len(sys.argv) < 2 or sys.argv[1] not in ENVIRONMENTS:
        print(f"usage: {sys.argv[0]} <{'|'.join(ENVIRONMENTS)}> [--force]")
        return 2
    env = sys.argv[1]
    force = "--force" in sys.argv
    files = {
        repo: ROOT / repo / f".env.{env}.local"
        for repo in ("likho-infra", "likho-language", "likho-media", "likho-transcription", "likho-api", "likho-search", "likho-connector-ameyo")
    }
    existing = [p for p in files.values() if p.exists()]
    if existing and not force:
        print("already there (use --force to replace):")
        for p in existing:
            print(f"  {p}")
        return 1

    values = {
        "POSTGRES_PASSWORD": token(24),
        "LIKHO_API_DB_PASSWORD": token(24),
        "LIKHO_MEDIA_DB_PASSWORD": token(24),
        "LIKHO_LANGUAGE_DB_PASSWORD": token(24),
        "LIKHO_CONNECTOR_DB_PASSWORD": token(24),
        "MONGO_ROOT_PASSWORD": token(24),
        "MONGO_PASSWORD": token(24),
        "S3_ACCESS_KEY": "likho-" + env,
        "S3_SECRET_KEY": token(32),
        "MEILI_MASTER_KEY": token(32),
        "LINK_SECRET": token(48),
        "SESSION_SECRET": token(48),
        "BOOTSTRAP_ADMIN_PASSWORD": token(18),
        "PUBLIC_DOMAIN": f"CHANGE-ME.{env}.example.com",
        "BOOTSTRAP_ADMIN_EMAIL": "CHANGE-ME@example.com",
    }
    head = f"# Secrets of the {env} environment. Ignored by git. Made by likho-infra/scripts/make-env-secrets.py.\n\n"

    files["likho-infra"].write_text(
        head + "".join(f"{k}={v}\n" for k, v in values.items()), encoding="utf-8", newline="\n"
    )
    files["likho-language"].write_text(
        head
        + f"DATABASE_URL=postgresql+asyncpg://likho_language:{values['LIKHO_LANGUAGE_DB_PASSWORD']}@postgres:5432/likho_language\n",
        encoding="utf-8",
        newline="\n",
    )
    files["likho-media"].write_text(
        head
        + f"DATABASE_URL=postgres://likho_media:{values['LIKHO_MEDIA_DB_PASSWORD']}@postgres:5432/likho_media\n"
        + f"S3_ACCESS_KEY={values['S3_ACCESS_KEY']}\n"
        + f"S3_SECRET_KEY={values['S3_SECRET_KEY']}\n"
        + f"LINK_SECRET={values['LINK_SECRET']}\n"
        + f"PUBLIC_URL=https://{values['PUBLIC_DOMAIN']}\n",
        encoding="utf-8",
        newline="\n",
    )
    files["likho-transcription"].write_text(
        head + f"MONGO_URL=mongodb://likho_transcription:{values['MONGO_PASSWORD']}@mongo:27017/likho_transcription?authSource=admin\n",
        encoding="utf-8",
        newline="\n",
    )
    files["likho-api"].write_text(
        head
        + f"DATABASE_URL=postgres://likho_api:{values['LIKHO_API_DB_PASSWORD']}@postgres:5432/likho_api\n"
        + f"SESSION_SECRET={values['SESSION_SECRET']}\n"
        + f"BOOTSTRAP_ADMIN_EMAIL={values['BOOTSTRAP_ADMIN_EMAIL']}\n"
        + f"BOOTSTRAP_ADMIN_PASSWORD={values['BOOTSTRAP_ADMIN_PASSWORD']}\n"
        + f"PUBLIC_ORIGIN=https://{values['PUBLIC_DOMAIN']}\n",
        encoding="utf-8",
        newline="\n",
    )
    files["likho-search"].write_text(
        head + f"MEILI_API_KEY={values['MEILI_MASTER_KEY']}\n", encoding="utf-8", newline="\n"
    )
    files["likho-connector-ameyo"].write_text(
        head
        + f"DATABASE_URL=postgres://likho_connector:{values['LIKHO_CONNECTOR_DB_PASSWORD']}@postgres:5432/likho_connector\n"
        + "# The workspace's API key (Settings -> API keys in the web app) and its id:\n"
        + "LIKHO_API_KEY=CHANGE-ME\n"
        + "WORKSPACE_ID=CHANGE-ME\n"
        + "# The dialer's voice-log API and its credentials (the company's; never committed):\n"
        + "AMEYO_VOICELOG_URL=CHANGE-ME\n"
        + "AMEYO_HASH_KEY=CHANGE-ME\n"
        + "AMEYO_POLICY_NAME=CHANGE-ME\n"
        + "AMEYO_REQUESTING_HOST=CHANGE-ME\n"
        + "# Optional: the dialer's reporting database (read only) and the CRM, with the real queries:\n"
        + "# DIALER_DATABASE_URL=postgres://user:password@host:5432/dialer\n"
        + "# CALLS_QUERY_FILE=queries/calls.local.sql\n"
        + "# CALL_QUERY_FILE=queries/call.local.sql\n"
        + "# CRM_DATABASE_URL=Server=host,1433;Database=crm;User Id=user;Password=password;Encrypt=false\n"
        + "# WRITEBACK_QUERY_FILE=queries/writeback.local.sql\n",
        encoding="utf-8",
        newline="\n",
    )
    for path in files.values():
        print(f"wrote {path}")
    print("fill in: PUBLIC_DOMAIN / PUBLIC_URL / PUBLIC_ORIGIN (the domain), BOOTSTRAP_ADMIN_EMAIL, and the connector's API key and dialer values")
    return 0


if __name__ == "__main__":
    sys.exit(main())
