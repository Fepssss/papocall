import nodemailer, { Transporter } from 'nodemailer';
import { env } from '../config/env';

/**
 * Serviço de Envio de E-mails Transacionais (Verificação de Conta e Reset de Senha).
 *
 * REGRA DE SEGURANÇA:
 * O token em texto puro NUNCA pode aparecer em log de produção. Quem tiver
 * acesso aos logs (equipe, plataforma de observabilidade, um vazamento de
 * bucket) conseguiria redefinir a senha de qualquer conta apenas lendo o token
 * impresso. Em produção o token só trafega pelo corpo do e-mail.
 */

export interface EmailService {
  sendVerificationEmail(to: string, username: string, token: string): Promise<void>;
  sendPasswordResetEmail(to: string, username: string, token: string): Promise<void>;
}

class SmtpEmailService implements EmailService {
  private transporter: Transporter | null = null;

  private isProduction(): boolean {
    return env.NODE_ENV === 'production';
  }

  private getTransporter(): Transporter | null {
    if (!env.SMTP_HOST) return null;
    if (this.transporter) return this.transporter;

    this.transporter = nodemailer.createTransport({
      host: env.SMTP_HOST,
      port: env.SMTP_PORT,
      // 465 usa TLS implícito; nas demais portas o STARTTLS é exigido abaixo.
      secure: env.SMTP_PORT === 465,
      requireTLS: env.SMTP_PORT !== 465,
      auth: env.SMTP_USER && env.SMTP_PASS
        ? { user: env.SMTP_USER, pass: env.SMTP_PASS }
        : undefined,
      connectionTimeout: 6000,
      greetingTimeout: 6000,
      socketTimeout: 10000,
    });

    return this.transporter;
  }

  private async deliver(to: string, subject: string, html: string, devPreview: () => void): Promise<void> {
    const transporter = this.getTransporter();

    if (!transporter) {
      // Em produção, sem SMTP não há como entregar o token com segurança.
      // Falhar alto é melhor do que imprimi-lo em log ou fingir que enviou.
      if (this.isProduction()) {
        throw new Error(
          'SMTP_HOST não configurado: o envio de e-mails transacionais é obrigatório em produção.'
        );
      }
      devPreview();
      return;
    }

    await transporter.sendMail({ from: env.EMAIL_FROM, to, subject, html });
  }

  async sendVerificationEmail(to: string, username: string, token: string): Promise<void> {
    const verificationUrl = `${env.FRONTEND_URL}/verify-email?token=${encodeURIComponent(token)}`;

    await this.deliver(
      to,
      'Confirme seu e-mail no PapoCall',
      `<p>Olá, @${username}!</p>
       <p>Confirme seu endereço de e-mail para ativar sua conta no PapoCall:</p>
       <p><a href="${verificationUrl}">Confirmar meu e-mail</a></p>
       <p>Este link expira em 24 horas.</p>`,
      () => {
        console.log('------------------------------------------------------------');
        console.log(`[MOCK EMAIL - DEV] Para: ${to} (@${username})`);
        console.log(`Link de Verificação: ${verificationUrl}`);
        console.log('------------------------------------------------------------');
      }
    );
  }

  async sendPasswordResetEmail(to: string, username: string, token: string): Promise<void> {
    const resetUrl = `${env.FRONTEND_URL}/reset-password?token=${encodeURIComponent(token)}`;

    await this.deliver(
      to,
      'Redefinição de senha no PapoCall',
      `<p>Olá, @${username}!</p>
       <p>Recebemos um pedido para redefinir a senha da sua conta.</p>
       <p><a href="${resetUrl}">Redefinir minha senha</a></p>
       <p>Este link expira em 20 minutos. Se não foi você que pediu, ignore esta mensagem.</p>`,
      () => {
        console.log('------------------------------------------------------------');
        console.log(`[MOCK EMAIL - DEV] Para: ${to} (@${username})`);
        console.log(`Link de Redefinição: ${resetUrl}`);
        console.log('------------------------------------------------------------');
      }
    );
  }
}

export const emailService: EmailService = new SmtpEmailService();
