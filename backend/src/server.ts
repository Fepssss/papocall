import { app } from './app';
import { env } from './config/env';
import { prisma } from './db/prisma';

const server = app.listen(env.PORT, () => {
  console.log(`========================================================`);
  console.log(`🚀 PapoCall Auth Service rodando com sucesso!`);
  console.log(`📡 Porta: ${env.PORT}`);
  console.log(`🌍 Ambiente: ${env.NODE_ENV}`);
  console.log(`🔐 Assinatura JWT: RS256 (RSA 2048-bit)`);
  console.log(`🛡️  Hash de Senhas: Argon2id`);
  console.log(`🔗 Health Check: http://localhost:${env.PORT}/health`);
  console.log(`========================================================`);
});

// Encerramento gracioso (Graceful Shutdown)
async function gracefulShutdown(signal: string) {
  console.log(`\n🛑 Recebido sinal ${signal}. Encerrando servidor com segurança...`);
  server.close(async () => {
    try {
      await prisma.$disconnect();
      console.log('✅ Conexão com o banco de dados encerrada.');
      process.exit(0);
    } catch (err) {
      console.error('❌ Erro ao desconectar banco de dados:', err);
      process.exit(1);
    }
  });
}

process.on('SIGINT', () => gracefulShutdown('SIGINT'));
process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
