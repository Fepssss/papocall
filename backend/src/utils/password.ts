import { hash, verify, Algorithm } from '@node-rs/argon2';

/**
 * Utilitários de Criptografia para Senhas com Argon2id.
 *
 * POR QUE ARGON2ID EM VEZ DE BCRYPT?
 * 1. Vencedor do Password Hashing Competition (PHC) em 2015.
 * 2. Argon2id é uma variante híbrida que combina:
 *    - Argon2d: Resistente a ataques de computação paralela massiva por hardware (GPU/ASIC).
 *    - Argon2i: Resistente a ataques de canal lateral (side-channel cache-timing attacks).
 * 3. Bcrypt trunca senhas silenciosamente em 72 bytes. Argon2id não possui essa limitação.
 * 4. Permite parametrização de memória (memoryCost), tempo (timeCost) e threads (parallelism).
 * 5. Possui proteção nativa em tempo constante contra timing attacks durante a verificação.
 */

// Parâmetros recomendados pela OWASP para Argon2id em servidores web modernos
const ARGON2_CONFIG = {
  algorithm: Algorithm.Argon2id,
  memoryCost: 19456, // 19 MB de alocação de memória RAM por hash
  timeCost: 2,       // 2 iterações
  parallelism: 1,    // 1 thread
};

// Hash fictício pré-computado para comparação em tempo constante quando usuário não é encontrado
const DUMMY_HASH =
  '$argon2id$v=19$m=19456,t=2,p=1$128DyQcYKw0I3CVk1BXQaw$eyjaZdNO6hEu4+4PlY2tAVc/6RP0Lb/N4te3E4D8rkk';

/**
 * Gera o hash criptográfico seguro da senha utilizando Argon2id.
 */
export async function hashPassword(plainPassword: string): Promise<string> {
  return hash(plainPassword, ARGON2_CONFIG);
}

/**
 * Verifica se uma senha informada corresponde ao hash armazenado.
 * Implementa verificação em tempo constante nativa da biblioteca.
 */
export async function verifyPassword(storedHash: string, plainPassword: string): Promise<boolean> {
  try {
    return await verify(storedHash, plainPassword);
  } catch {
    return false;
  }
}

/**
 * Executa uma verificação dummy de tempo constante para mitigar timing attacks
 * quando o usuário ou e-mail pesquisado não existir no banco de dados.
 * Isso impede que atacantes façam enumeração de contas comparando a latência da resposta.
 */
export async function dummyVerifyPassword(): Promise<void> {
  try {
    await verify(DUMMY_HASH, 'dummy_fallback_timing_attack_mitigation');
  } catch {
    // Ignorado intencionalmente
  }
}
