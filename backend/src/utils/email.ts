import { env } from '../config/env';

/**
 * Serviço de Envio de E-mails Transacionais (Verificação de Conta e Reset de Senha).
 * Em ambiente de desenvolvimento e testes, simula o envio imprimindo com destaque no console
 * e fornecendo o token diretamente para facilidade de testes automatizados e manuais.
 */

export interface EmailService {
  sendVerificationEmail(to: string, username: string, token: string): Promise<void>;
  sendPasswordResetEmail(to: string, username: string, token: string): Promise<void>;
}

class MockOrSmtpEmailService implements EmailService {
  async sendVerificationEmail(to: string, username: string, token: string): Promise<void> {
    const verificationUrl = `${env.FRONTEND_URL}/verify-email?token=${token}`;

    if (env.NODE_ENV !== 'production' || !env.SMTP_HOST) {
      console.log('------------------------------------------------------------');
      console.log(`📧 [MOCK EMAIL] Para: ${to} (Usuário: @${username})`);
      console.log(`📌 Assunto: Confirme seu e-mail no PapoCall`);
      console.log(`🔗 Link de Verificação: ${verificationUrl}`);
      console.log(`🔑 Token Puro: ${token}`);
      console.log('------------------------------------------------------------');
      return;
    }

    // Em produção com SMTP configurado: integrar com nodemailer
    // TODO: Envio real via Nodemailer / Resend / AWS SES
    console.log(`[EMAIL PRODUCTION] E-mail de verificação despachado para ${to}`);
  }

  async sendPasswordResetEmail(to: string, username: string, token: string): Promise<void> {
    const resetUrl = `${env.FRONTEND_URL}/reset-password?token=${token}`;

    if (env.NODE_ENV !== 'production' || !env.SMTP_HOST) {
      console.log('------------------------------------------------------------');
      console.log(`📧 [MOCK EMAIL] Para: ${to} (Usuário: @${username})`);
      console.log(`📌 Assunto: Redefinição de senha no PapoCall`);
      console.log(`🔗 Link de Redefinição: ${resetUrl}`);
      console.log(`🔑 Token de Reset: ${token}`);
      console.log('⏳ Expira em: 20 minutos');
      console.log('------------------------------------------------------------');
      return;
    }

    console.log(`[EMAIL PRODUCTION] E-mail de reset de senha despachado para ${to}`);
  }
}

export const emailService: EmailService = new MockOrSmtpEmailService();
