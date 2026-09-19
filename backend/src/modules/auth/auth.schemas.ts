import { z } from 'zod';

/**
 * Função utilitária para normalizar o username:
 * 1. Remove espaços em branco ao redor.
 * 2. Remove o prefixo '@' se tiver sido digitado pelo usuário.
 * 3. Converte para minúsculas (lowercase) para garantir unicidade case-insensitive.
 */
export function normalizeUsername(raw: string): string {
  let cleaned = raw.trim();
  if (cleaned.startsWith('@')) {
    cleaned = cleaned.substring(1);
  }
  return cleaned.toLowerCase();
}

/**
 * Regex para username: apenas letras (a-z), números (0-9) e underscore (_).
 * Sem espaços, sem pontuações especiais.
 */
const USERNAME_REGEX = /^[a-zA-Z0-9_]+$/;

/**
 * Validação de Senha Forte:
 * - Mínimo 8 caracteres
 * - Pelo menos uma letra maiúscula (A-Z)
 * - Pelo menos um número (0-9)
 */
const PASSWORD_REGEX = /^(?=.*[A-Z])(?=.*\d).{8,}$/;

export const RegisterSchema = z.object({
  email: z
    .string({ required_error: 'E-mail é obrigatório.' })
    .email('Formato de e-mail inválido.')
    .transform((val) => val.trim().toLowerCase()),

  password: z
    .string({ required_error: 'Senha é obrigatória.' })
    .min(8, 'A senha deve ter no mínimo 8 caracteres.')
    // Teto recomendado pela OWASP: o Argon2id aloca 19 MB por hash, então
    // senhas gigantes viram um vetor barato de esgotamento de memória.
    .max(128, 'A senha pode ter no máximo 128 caracteres.')
    .regex(
      PASSWORD_REGEX,
      'A senha deve conter pelo menos uma letra maiúscula e pelo menos um número.'
    ),

  displayName: z
    .string({ required_error: 'Nome de exibição é obrigatório.' })
    .min(1, 'Nome de exibição não pode estar vazio.')
    .max(50, 'Nome de exibição pode ter no máximo 50 caracteres.')
    .transform((val) => val.trim()),

  username: z
    .string({ required_error: 'Nome de usuário (@username) é obrigatório.' })
    .transform((val) => normalizeUsername(val))
    .refine(
      (val) => val.length >= 3 && val.length <= 20,
      'O nome de usuário deve ter entre 3 e 20 caracteres.'
    )
    .refine(
      (val) => USERNAME_REGEX.test(val),
      'O nome de usuário pode conter apenas letras, números e underscore (_).'
    ),
});

export const LoginSchema = z.object({
  // Aceita tanto e-mail quanto @username
  identifier: z
    .string({ required_error: 'E-mail ou @username é obrigatório.' })
    .min(1, 'Informe seu e-mail ou @username.')
    .max(254, 'Identificador muito longo.')
    .transform((val) => val.trim()),

  password: z
    .string({ required_error: 'Senha é obrigatória.' })
    .min(1, 'Informe sua senha.')
    // Sem teto aqui, o dummy-verify do Argon2id (19 MB por hash) passa a ser um
    // vetor de esgotamento de memória acionável por qualquer pessoa, sem conta.
    .max(128, 'A senha pode ter no máximo 128 caracteres.'),
});

export const RefreshTokenSchema = z.object({
  refreshToken: z
    .string({ required_error: 'Refresh token é obrigatório.' })
    .min(1, 'Refresh token não pode ser vazio.'),
});

export const LogoutSchema = z.object({
  refreshToken: z
    .string({ required_error: 'Refresh token é obrigatório.' })
    .min(1, 'Refresh token não pode ser vazio.'),
});

export const VerifyEmailSchema = z.object({
  token: z
    .string({ required_error: 'Token de verificação é obrigatório.' })
    .min(1, 'Token não pode ser vazio.'),
});

export const ForgotPasswordSchema = z.object({
  email: z
    .string({ required_error: 'E-mail é obrigatório.' })
    .email('Formato de e-mail inválido.')
    .transform((val) => val.trim().toLowerCase()),
});

export const ResetPasswordSchema = z.object({
  token: z
    .string({ required_error: 'Token de recuperação é obrigatório.' })
    .min(1, 'Token não pode ser vazio.'),

  newPassword: z
    .string({ required_error: 'Nova senha é obrigatória.' })
    .min(8, 'A nova senha deve ter no mínimo 8 caracteres.')
    .max(128, 'A nova senha pode ter no máximo 128 caracteres.')
    .regex(
      PASSWORD_REGEX,
      'A nova senha deve conter pelo menos uma letra maiúscula e pelo menos um número.'
    ),
});

export const UsernameAvailableSchema = z.object({
  username: z
    .string({ required_error: 'Parâmetro username é obrigatório.' })
    .transform((val) => normalizeUsername(val))
    .refine(
      (val) => val.length >= 3 && val.length <= 20,
      'O nome de usuário deve ter entre 3 e 20 caracteres.'
    )
    .refine(
      (val) => USERNAME_REGEX.test(val),
      'O nome de usuário pode conter apenas letras, números e underscore (_).'
    ),
});

export const ChangeUsernameSchema = z.object({
  newUsername: z
    .string({ required_error: 'Novo nome de usuário (@username) é obrigatório.' })
    .transform((val) => normalizeUsername(val))
    .refine(
      (val) => val.length >= 3 && val.length <= 20,
      'O nome de usuário deve ter entre 3 e 20 caracteres.'
    )
    .refine(
      (val) => USERNAME_REGEX.test(val),
      'O nome de usuário pode conter apenas letras, números e underscore (_).'
    ),
});

/**
 * Identificador de sala restrito a um conjunto seguro de caracteres.
 * Sem isso, o cliente poderia pedir um nome de sala arbitrário e usar o token
 * do LiveKit para entrar em qualquer conferência do projeto.
 */
export const LivekitTokenSchema = z.object({
  room: z
    .string()
    .min(1, 'Identificador de sala não pode ser vazio.')
    .max(64, 'Nome da sala muito longo.')
    .regex(
      /^[a-zA-Z0-9_-]+$/,
      'Identificador de sala inválido: use apenas letras, números, hífen e underscore.'
    )
    .default('v-geral'),
});
