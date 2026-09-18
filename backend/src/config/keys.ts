import crypto from 'node:crypto';
import { env } from './env';

/**
 * Gerenciamento de chaves assimétricas RSA para algoritmo RS256.
 *
 * POR QUE RS256 EM VEZ DE HS256?
 * 1. Chave Assimétrica: A Chave Privada é mantida estritamente protegida no serviço
 *    de autenticação para assinar os tokens (JWTs).
 * 2. Qualquer outro serviço, microserviço, gateway ou serviço LiveKit precisa apenas
 *    da Chave Pública para verificar a autenticidade do token.
 * 3. Se a Chave Pública vazar, o atacante NÃO consegue forjar tokens (ao contrário do HS256,
 *    onde o mesmo secret compartilhado permite forjar tokens de qualquer usuário).
 */

interface KeyPair {
  privateKey: string;
  publicKey: string;
}

let loadedKeys: KeyPair | null = null;

function normalizePem(key: string): string {
  // Suporte para chaves passadas em Base64 ou com quebras de linha escapadas (\n)
  let clean = key.trim();
  if (!clean.includes('-----BEGIN')) {
    try {
      clean = Buffer.from(clean, 'base64').toString('utf8');
    } catch {
      // Deixa o parser padrão avaliar se falhar
    }
  }
  return clean.replace(/\\n/g, '\n');
}

export function getJwtKeys(): KeyPair {
  if (loadedKeys) {
    return loadedKeys;
  }

  const rawPrivate = env.JWT_PRIVATE_KEY;
  const rawPublic = env.JWT_PUBLIC_KEY;

  if (rawPrivate && rawPublic) {
    loadedKeys = {
      privateKey: normalizePem(rawPrivate),
      publicKey: normalizePem(rawPublic),
    };
    return loadedKeys;
  }

  // Se estiver em produção e as chaves não foram configuradas, aborta com erro explícito
  if (env.NODE_ENV === 'production') {
    throw new Error(
      'EM PRODUÇÃO: JWT_PRIVATE_KEY e JWT_PUBLIC_KEY devem ser configuradas obrigatoriamente no .env com chaves RSA válidas.'
    );
  }

  // Em desenvolvimento e testes: Gera par de chaves RSA 2048 bits efêmero automaticamente
  console.warn(
    '⚠️ [AVISO DE DEV] Chaves RS256 não informadas. Gerando par de chaves RSA 2048 bits efêmero em memória para desenvolvimento...'
  );

  const { privateKey, publicKey } = crypto.generateKeyPairSync('rsa', {
    modulusLength: 2048,
    publicKeyEncoding: {
      type: 'spki',
      format: 'pem',
    },
    privateKeyEncoding: {
      type: 'pkcs8',
      format: 'pem',
    },
  });

  loadedKeys = { privateKey, publicKey };
  return loadedKeys;
}
