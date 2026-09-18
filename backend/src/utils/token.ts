import crypto from 'node:crypto';
import jwt, { SignOptions } from 'jsonwebtoken';
import { env } from '../config/env';
import { getJwtKeys } from '../config/keys';

/**
 * Utilitários para Emissão e Validação de Tokens JWT (RS256) e Hashes de Tokens (SHA-256).
 */

export interface AccessTokenPayload {
  sub: string;           // ID único do usuário
  email: string;         // E-mail do usuário
  username: string;      // Username único estilo Twitter (ex: 'joaosilva')
  displayName: string;   // Nome de exibição
  emailVerified: boolean;// Status de confirmação do e-mail
}

export interface DecodedToken extends AccessTokenPayload {
  iat: number;
  exp: number;
  iss: string;
}

const TOKEN_ISSUER = 'papocall-auth';

/**
 * Emite um Access Token JWT assinado assimetricamente com RS256 e a Chave Privada.
 */
export function generateAccessToken(payload: AccessTokenPayload): string {
  const { privateKey } = getJwtKeys();

  const options: SignOptions = {
    algorithm: 'RS256',
    expiresIn: env.JWT_ACCESS_EXPIRATION as SignOptions['expiresIn'],
    issuer: TOKEN_ISSUER,
  };

  return jwt.sign(payload, privateKey, options);
}

/**
 * Valida a assinatura de um Access Token JWT utilizando exclusivamente a Chave Pública (RS256).
 * Se a chave for alterada ou o token estiver expirado/violado, lança exceção do JWT.
 */
export function verifyAccessToken(token: string): DecodedToken {
  const { publicKey } = getJwtKeys();

  return jwt.verify(token, publicKey, {
    algorithms: ['RS256'],
    issuer: TOKEN_ISSUER,
  }) as DecodedToken;
}

/**
 * Gera um token aleatório de alta entropia criptográfica (256 bits).
 * Adequado para refresh tokens, tokens de ativação de e-mail e recuperação de senha.
 */
export function generateRandomToken(bytes = 32): string {
  return crypto.randomBytes(bytes).toString('hex');
}

/**
 * Calcula o hash SHA-256 de um token antes de salvar no banco de dados.
 *
 * REGRA DE SEGURANÇA:
 * NUNCA armazenar refresh tokens ou tokens de reset em texto puro no banco de dados.
 * Se o banco de dados vazar, atacantes não conseguem utilizar os hashes SHA-256
 * para se autenticar sem conhecer os tokens de alta entropia originais.
 */
export function hashToken(token: string): string {
  return crypto.createHash('sha256').update(token).digest('hex');
}
