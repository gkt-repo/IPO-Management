import { Prisma } from '@prisma/client';

// Serialize PAN changes and refresh admission across all backend instances.
export async function lockUser(tx: Prisma.TransactionClient, userId: string) {
  await tx.$queryRaw`SELECT id FROM users WHERE id = ${userId} FOR UPDATE`;
}
