import crypto from 'node:crypto';
import { prisma } from '../../db/prisma';
import { AppError } from '../../middlewares/error.middleware';
import { hashPassword, verifyPassword, dummyVerifyPassword } from '../../utils/password';
import {
  generateAccessToken,
  generateRandomToken,
  hashToken,
  AccessTokenPayload,
} from '../../utils/token';
import { emailService } from '../../utils/email';
import { logSecurityEvent } from '../../utils/logger';
import { normalizeUsername } from './auth.schemas';

export interface UserResponse {
  id: string;
  email: string;
  username: string; // Exibido sempre com prefixo '@'
  rawUsername: string; // Sem '@'
  displayName: string;
  emailVerified: boolean;
  createdAt: Date;
}

export interface AuthSessionResponse {
  user: UserResponse;
  accessToken: string;
  refreshToken: string;
}

function formatUser(u: {
  id: string;
  email: string;
  username: string;
  display_name: string;
  email_verified: boolean;
  created_at: Date;
}): UserResponse {
  return {
    id: u.id,
    email: u.email,
    username: `@${u.username}`,
    rawUsername: u.username,
    displayName: u.display_name,
    emailVerified: u.email_verified,
    createdAt: u.created_at,
  };
}

export class AuthService {
  /**
   * 1. Registro de Usuário com Username Único e Hash Argon2id.
   */
  async register(params: {
    email: string;
    username: string;
    displayName: string;
    password: string;
    ip?: string;
  }): Promise<AuthSessionResponse> {
    const { email, username, displayName, password, ip } = params;

    // Verifica duplicação de e-mail
    const existingEmail = await prisma.user.findUnique({
      where: { email },
    });
    if (existingEmail) {
      throw new AppError(
        'Este endereço de e-mail já está cadastrado em outra conta.',
        409,
        'EMAIL_ALREADY_EXISTS'
      );
    }

    // Verifica duplicação de username (case-insensitive já garantido pelo lowercase)
    const existingUsername = await prisma.user.findUnique({
      where: { username },
    });
    if (existingUsername) {
      const suggestions = await this.generateUsernameSuggestions(username);
      throw new AppError(
        `O nome de usuário '@${username}' já está em uso.`,
        409,
        'USERNAME_ALREADY_EXISTS',
        { suggestions }
      );
    }

    // Hash da senha com Argon2id
    const passwordHash = await hashPassword(password);

    // Cria o usuário no banco de dados
    const user = await prisma.user.create({
      data: {
        email,
        username,
        display_name: displayName,
        password_hash: passwordHash,
        email_verified: false,
      },
    });

    // Gera token de verificação de e-mail (válido por 24 horas)
    const verificationToken = generateRandomToken();
    await prisma.emailVerificationToken.create({
      data: {
        user_id: user.id,
        token_hash: hashToken(verificationToken),
        expires_at: new Date(Date.now() + 24 * 60 * 60 * 1000),
      },
    });

    // A conta já foi criada; o envio de e-mail é despachado de forma resiliente sem bloquear o tempo de resposta do cliente.
    emailService.sendVerificationEmail(user.email, user.username, verificationToken).catch((error) => {
      console.error('[EMAIL] Falha ao enviar e-mail de verificação em background:', error);
    });

    // Cria a sessão inicial do usuário
    const session = await this.createSession(user, ip);

    logSecurityEvent({
      event: 'USER_REGISTERED',
      userId: user.id,
      username: `@${user.username}`,
      ip,
    });

    return session;
  }

  /**
   * 2. Verificação de Disponibilidade de Username em Tempo Real com Sugestões.
   */
  async checkUsernameAvailability(username: string): Promise<{
    available: boolean;
    username: string;
    suggestions?: string[];
  }> {
    const existing = await prisma.user.findUnique({
      where: { username },
      select: { id: true },
    });

    if (!existing) {
      return {
        available: true,
        username: `@${username}`,
      };
    }

    const suggestions = await this.generateUsernameSuggestions(username);
    return {
      available: false,
      username: `@${username}`,
      suggestions,
    };
  }

  /**
   * 3. Login por E-mail OU @Username + Senha.
   */
  async login(params: {
    identifier: string;
    password: string;
    ip?: string;
  }): Promise<AuthSessionResponse> {
    const { identifier, password, ip } = params;

    const isEmail = identifier.includes('@') && identifier.includes('.');
    const cleanUsername = normalizeUsername(identifier);

    // Busca usuário por e-mail ou username normalizado
    const user = await prisma.user.findFirst({
      where: isEmail
        ? { OR: [{ email: identifier.toLowerCase() }, { username: cleanUsername }] }
        : { OR: [{ username: cleanUsername }, { email: identifier.toLowerCase() }] },
    });

    // Mitigação de timing attack se o usuário não for encontrado
    if (!user) {
      await dummyVerifyPassword();
      // Não registra o identificador digitado: usuários ocasionalmente digitam
      // a senha no campo de e-mail, o que gravaria a senha no log de auditoria.
      logSecurityEvent({
        event: 'LOGIN_FAILED',
        ip,
        details: { reason: 'USER_NOT_FOUND' },
      });
      throw new AppError(
        'Credenciais inválidas. Verifique seu e-mail/username e senha.',
        401,
        'INVALID_CREDENTIALS'
      );
    }

    // Verificação da senha com Argon2id
    const passwordMatch = await verifyPassword(user.password_hash, password);
    if (!passwordMatch) {
      logSecurityEvent({
        event: 'LOGIN_FAILED',
        userId: user.id,
        username: `@${user.username}`,
        ip,
        details: { reason: 'WRONG_PASSWORD' },
      });
      throw new AppError(
        'Credenciais inválidas. Verifique seu e-mail/username e senha.',
        401,
        'INVALID_CREDENTIALS'
      );
    }

    const session = await this.createSession(user, ip);

    logSecurityEvent({
      event: 'LOGIN_SUCCESS',
      userId: user.id,
      username: `@${user.username}`,
      ip,
    });

    return session;
  }

  /**
   * 4. Rotação de Refresh Token com Detecção e Bloqueio de Reuso.
   */
  async refreshAccessToken(rawRefreshToken: string, ip?: string): Promise<{
    accessToken: string;
    refreshToken: string;
  }> {
    const incomingTokenHash = hashToken(rawRefreshToken);

    const tokenRecord = await prisma.refreshToken.findUnique({
      where: { token_hash: incomingTokenHash },
      include: { user: true },
    });

    if (!tokenRecord) {
      throw new AppError('Sessão inválida. Faça login novamente.', 401, 'INVALID_REFRESH_TOKEN');
    }

    // =========================================================================
    // DETECÇÃO CRÍTICA DE REUSO DE REFRESH TOKEN (Gatilho de Comprometimento)
    // =========================================================================
    // Se o token recebido já tiver sido revogado anteriormente, significa que ou
    // um atacante ou a vítima está tentando usar um token antigo que já sofreu rotação.
    // Ação imediata: revoga TODAS as sessões ativas do usuário para conter o ataque.
    if (tokenRecord.revoked) {
      await prisma.refreshToken.updateMany({
        where: { user_id: tokenRecord.user_id },
        data: { revoked: true, revoked_at: new Date() },
      });

      logSecurityEvent({
        event: 'TOKEN_REUSE_DETECTED',
        userId: tokenRecord.user_id,
        username: `@${tokenRecord.user.username}`,
        ip,
        details: { familyId: tokenRecord.family_id },
      });

      throw new AppError(
        'Possível comprometimento de sessão detectado. Por segurança, todas as suas sessões foram encerradas. Faça login novamente.',
        401,
        'TOKEN_REUSE_DETECTED'
      );
    }

    // Verifica expiração
    if (tokenRecord.expires_at < new Date()) {
      throw new AppError('Sua sessão expirou. Faça login novamente.', 401, 'REFRESH_TOKEN_EXPIRED');
    }

    // Rotaciona o token: invalida o token atual
    await prisma.refreshToken.update({
      where: { id: tokenRecord.id },
      data: { revoked: true, revoked_at: new Date() },
    });

    // Emite um novo Refresh Token na mesma família (family_id)
    const newRefreshToken = generateRandomToken();
    const newExpiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);

    await prisma.refreshToken.create({
      data: {
        user_id: tokenRecord.user_id,
        token_hash: hashToken(newRefreshToken),
        family_id: tokenRecord.family_id,
        expires_at: newExpiresAt,
      },
    });

    // Emite um novo Access Token JWT RS256
    const payload: AccessTokenPayload = {
      sub: tokenRecord.user.id,
      email: tokenRecord.user.email,
      username: tokenRecord.user.username,
      displayName: tokenRecord.user.display_name,
      emailVerified: tokenRecord.user.email_verified,
    };
    const newAccessToken = generateAccessToken(payload);

    logSecurityEvent({
      event: 'TOKEN_REFRESHED',
      userId: tokenRecord.user.id,
      username: `@${tokenRecord.user.username}`,
      ip,
    });

    return {
      accessToken: newAccessToken,
      refreshToken: newRefreshToken,
    };
  }

  /**
   * 5. Logout de Sessão Única (Invalida o refresh token atual).
   */
  async logout(rawRefreshToken: string, ip?: string): Promise<void> {
    const tokenHash = hashToken(rawRefreshToken);

    const record = await prisma.refreshToken.findUnique({
      where: { token_hash: tokenHash },
    });

    if (record && !record.revoked) {
      await prisma.refreshToken.update({
        where: { id: record.id },
        data: { revoked: true, revoked_at: new Date() },
      });

      logSecurityEvent({
        event: 'LOGOUT',
        userId: record.user_id,
        ip,
      });
    }
  }

  /**
   * 6. Logout de Todas as Sessões (Revoga todos os refresh tokens do usuário).
   */
  async logoutAllSessions(userId: string, ip?: string): Promise<void> {
    await prisma.refreshToken.updateMany({
      where: { user_id: userId, revoked: false },
      data: { revoked: true, revoked_at: new Date() },
    });

    logSecurityEvent({
      event: 'LOGOUT_ALL_SESSIONS',
      userId,
      ip,
    });
  }

  /**
   * 7. Confirmação de E-mail.
   */
  async verifyEmail(rawToken: string, ip?: string): Promise<{ message: string }> {
    const tokenHash = hashToken(rawToken);

    const record = await prisma.emailVerificationToken.findUnique({
      where: { token_hash: tokenHash },
      include: { user: true },
    });

    if (!record || record.used || record.expires_at < new Date()) {
      throw new AppError(
        'Token de verificação inválido, expirado ou já utilizado.',
        400,
        'INVALID_VERIFICATION_TOKEN'
      );
    }

    await prisma.$transaction([
      prisma.emailVerificationToken.update({
        where: { id: record.id },
        data: { used: true },
      }),
      prisma.user.update({
        where: { id: record.user_id },
        data: { email_verified: true },
      }),
    ]);

    logSecurityEvent({
      event: 'EMAIL_VERIFIED',
      userId: record.user_id,
      username: `@${record.user.username}`,
      ip,
    });

    return { message: 'Seu endereço de e-mail foi verificado com sucesso!' };
  }

  /**
   * 8. Recuperação de Senha - Solicitação (Esqueci minha senha).
   */
  async forgotPassword(email: string, ip?: string): Promise<{ message: string }> {
    const user = await prisma.user.findUnique({
      where: { email },
    });

    // Medida anti-enumeração: Retorna mensagem idêntica mesmo se o e-mail não existir
    if (!user) {
      await dummyVerifyPassword();
      return {
        message: 'Se este e-mail estiver cadastrado, você receberá as instruções para redefinição.',
      };
    }

    // Invalida tokens de reset anteriores não utilizados
    await prisma.passwordResetToken.updateMany({
      where: { user_id: user.id, used: false },
      data: { used: true },
    });

    // Gera token de uso único válido por 20 minutos
    const resetToken = generateRandomToken();
    await prisma.passwordResetToken.create({
      data: {
        user_id: user.id,
        token_hash: hashToken(resetToken),
        expires_at: new Date(Date.now() + 20 * 60 * 1000),
      },
    });

    // A falha de envio não pode alterar a resposta: se o e-mail existente
    // devolvesse 500 e o inexistente 200, a diferença revelaria quais contas
    // estão cadastradas.
    try {
      await emailService.sendPasswordResetEmail(user.email, user.username, resetToken);
    } catch (error) {
      console.error('[EMAIL] Falha ao enviar e-mail de redefinição de senha:', error);
    }

    logSecurityEvent({
      event: 'PASSWORD_RESET_REQUESTED',
      userId: user.id,
      username: `@${user.username}`,
      ip,
    });

    return {
      message: 'Se este e-mail estiver cadastrado, você receberá as instruções para redefinição.',
    };
  }

  /**
   * 8. Recuperação de Senha - Definição da Nova Senha.
   */
  async resetPassword(rawToken: string, newPassword: string, ip?: string): Promise<{ message: string }> {
    const tokenHash = hashToken(rawToken);

    const record = await prisma.passwordResetToken.findUnique({
      where: { token_hash: tokenHash },
      include: { user: true },
    });

    if (!record || record.used || record.expires_at < new Date()) {
      throw new AppError(
        'Token de recuperação inválido, expirado ou já utilizado.',
        400,
        'INVALID_RESET_TOKEN'
      );
    }

    const newHash = await hashPassword(newPassword);

    await prisma.$transaction([
      prisma.passwordResetToken.update({
        where: { id: record.id },
        data: { used: true },
      }),
      prisma.user.update({
        where: { id: record.user_id },
        data: { password_hash: newHash },
      }),
      // Revoga todas as sessões ativas imediatamente por segurança após troca de senha
      prisma.refreshToken.updateMany({
        where: { user_id: record.user_id, revoked: false },
        data: { revoked: true, revoked_at: new Date() },
      }),
    ]);

    logSecurityEvent({
      event: 'PASSWORD_RESET_COMPLETED',
      userId: record.user_id,
      username: `@${record.user.username}`,
      ip,
    });

    return {
      message: 'Sua senha foi redefinida com sucesso. Todas as sessões anteriores foram encerradas por segurança.',
    };
  }

  /**
   * 9. Alteração de Username com Throttle de 30 Dias.
   */
  async changeUsername(userId: string, newUsername: string, ip?: string): Promise<UserResponse> {
    const user = await prisma.user.findUnique({
      where: { id: userId },
    });

    if (!user) {
      throw new AppError('Usuário não encontrado.', 404, 'USER_NOT_FOUND');
    }

    if (user.username === newUsername) {
      return formatUser(user);
    }

    // Regra de segurança/antifraude: limitar troca a 1 vez a cada 30 dias
    if (user.last_username_change_at) {
      const THIRTY_DAYS_MS = 30 * 24 * 60 * 60 * 1000;
      const elapsed = Date.now() - user.last_username_change_at.getTime();
      if (elapsed < THIRTY_DAYS_MS) {
        const remainingDays = Math.ceil((THIRTY_DAYS_MS - elapsed) / (24 * 60 * 60 * 1000));
        throw new AppError(
          `Você só pode alterar seu @username uma vez a cada 30 dias. Tente novamente em ${remainingDays} dia(s).`,
          400,
          'USERNAME_CHANGE_THROTTLED',
          { remainingDays }
        );
      }
    }

    // Checa se o novo username já pertence a outro usuário
    const taken = await prisma.user.findUnique({
      where: { username: newUsername },
    });

    if (taken) {
      const suggestions = await this.generateUsernameSuggestions(newUsername);
      throw new AppError(
        `O nome de usuário '@${newUsername}' já está em uso.`,
        409,
        'USERNAME_ALREADY_EXISTS',
        { suggestions }
      );
    }

    const updated = await prisma.user.update({
      where: { id: userId },
      data: {
        username: newUsername,
        last_username_change_at: new Date(),
      },
    });

    logSecurityEvent({
      event: 'USERNAME_CHANGED',
      userId: user.id,
      username: `@${newUsername}`,
      ip,
      details: { previousUsername: `@${user.username}` },
    });

    return formatUser(updated);
  }

  /**
   * 11. Perfil do Usuário Autenticado (/auth/me).
   */
  async getMe(userId: string): Promise<UserResponse> {
    const user = await prisma.user.findUnique({
      where: { id: userId },
    });

    if (!user) {
      throw new AppError('Usuário não encontrado.', 404, 'USER_NOT_FOUND');
    }

    return formatUser(user);
  }

  /**
   * Cria uma sessão gerando par de Access Token (RS256) e Refresh Token (SHA-256).
   */
  private async createSession(
    user: {
      id: string;
      email: string;
      username: string;
      display_name: string;
      email_verified: boolean;
      created_at: Date;
    },
    _ip?: string
  ): Promise<AuthSessionResponse> {
    const familyId = crypto.randomUUID();
    const rawRefreshToken = generateRandomToken();
    const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);

    await prisma.refreshToken.create({
      data: {
        user_id: user.id,
        token_hash: hashToken(rawRefreshToken),
        family_id: familyId,
        expires_at: expiresAt,
      },
    });

    const payload: AccessTokenPayload = {
      sub: user.id,
      email: user.email,
      username: user.username,
      displayName: user.display_name,
      emailVerified: user.email_verified,
    };

    const accessToken = generateAccessToken(payload);

    return {
      user: formatUser(user),
      accessToken,
      refreshToken: rawRefreshToken,
    };
  }

  /**
   * Gera sugestões automáticas de username quando o desejado já estiver ocupado.
   */
  private async generateUsernameSuggestions(base: string): Promise<string[]> {
    const clean = base.replace(/[^a-zA-Z0-9_]/g, '').substring(0, 15);
    const candidates = [
      `${clean}1`,
      `${clean}_`,
      `${clean}2026`,
      `${clean}_call`,
      `${clean}${Math.floor(10 + Math.random() * 89)}`,
    ];

    const available: string[] = [];
    for (const cand of candidates) {
      if (cand.length >= 3 && cand.length <= 20) {
        const found = await prisma.user.findUnique({
          where: { username: cand.toLowerCase() },
          select: { id: true },
        });
        if (!found && !available.includes(`@${cand.toLowerCase()}`)) {
          available.push(`@${cand.toLowerCase()}`);
          if (available.length >= 3) break;
        }
      }
    }

    return available;
  }
}

export const authService = new AuthService();
