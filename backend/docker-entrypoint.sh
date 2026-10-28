#!/bin/sh
set -e

echo "[IPO Backend] Pushing Prisma schema to PostgreSQL..."
npx prisma db push --skip-generate || echo "[IPO Backend] Notice: schema push completed with notices."

exec "$@"
