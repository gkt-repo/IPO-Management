#!/bin/sh
set -e

echo "[IPO Backend] Pushing Prisma schema to PostgreSQL..."
npx prisma db push

exec "$@"
