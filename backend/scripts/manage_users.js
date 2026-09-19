const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

async function main() {
  const users = await prisma.user.findMany({
    orderBy: { created_at: 'desc' },
    select: { id: true, email: true, username: true, email_verified: true, created_at: true }
  });
  console.log('Total de usuários encontrados:', users.length);
  users.forEach((u, i) => {
    console.log(`[${i}] ID: ${u.id} | @${u.username} | ${u.email} | Verified: ${u.email_verified} | Criado: ${u.created_at.toISOString()}`);
  });
}

main().catch(console.error).finally(() => prisma.$disconnect());
