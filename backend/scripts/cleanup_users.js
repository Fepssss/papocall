const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

async function cleanup() {
  console.log('--- Iniciando limpeza da base de usuários Neon ---');
  
  const allUsers = await prisma.user.findMany({
    orderBy: { created_at: 'desc' },
    select: { id: true, username: true, email: true, created_at: true }
  });

  if (allUsers.length === 0) {
    console.log('Nenhum usuário encontrado na base.');
    return;
  }

  const latestUser = allUsers[0];
  const oldUsers = allUsers.slice(1);

  console.log(`Último usuário criado (será MANTIDO): ID=${latestUser.id}, @${latestUser.username}, ${latestUser.email} (Criado em: ${latestUser.created_at.toISOString()})`);
  console.log(`Quantidade de usuários antigos a serem excluídos: ${oldUsers.length}`);

  for (const oldUser of oldUsers) {
    console.log(`Excluindo usuário antigo: @${oldUser.username} (${oldUser.id})...`);
    await prisma.user.delete({ where: { id: oldUser.id } });
    console.log(`✅ Usuário @${oldUser.username} excluído.`);
  }

  // Marca o usuário mantido como verificado
  const updatedUser = await prisma.user.update({
    where: { id: latestUser.id },
    data: { email_verified: true },
    select: { id: true, username: true, email: true, email_verified: true }
  });

  console.log('--- Limpeza concluída com sucesso! ---');
  console.log('Usuário ativo restante no Neon:', updatedUser);
}

cleanup()
  .catch((err) => {
    console.error('Erro na limpeza:', err);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
