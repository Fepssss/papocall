/**
 * Verificação do envio de e-mail transacional depois do upgrade do nodemailer.
 *
 * Duas metades, cada uma provando uma coisa diferente:
 *
 *  1. ENTREGA — os dois métodos do `emailService` REAL são chamados contra um
 *     SMTP de verdade (Ethereal, STARTTLS na 587, autenticação), e a resposta do
 *     servidor é lida. Prova que as opções de transporte da v10 aceitam a nossa
 *     configuração e que a mensagem foi aceita para o destinatário.
 *  2. CONTEÚDO — as mesmas mensagens são compostas pelo composer do nodemailer
 *     em `streamTransport`, que devolve os bytes RFC 822 que seriam entregues.
 *     Prova que assunto, token e link estão na mensagem que sai.
 *
 * Não usa credencial nossa: o Ethereal é serviço público de teste de e-mail.
 *
 * Uso: npx cross-env NODE_ENV=test npx tsx scripts/verificar-envio-email.ts
 */
import nodemailer from 'nodemailer';

const TOKEN_VERIFICACAO = 'tok-verificacao-DEADBEEF';
const TOKEN_RESET = 'tok-reset-CAFEBABE';

type Envio = {
  para: string;
  assunto: string;
  /** O objeto de mensagem que o produto entregou ao nodemailer, tal e qual. */
  mail: Record<string, unknown>;
  aceita: boolean;
  respostaSmtp: string;
};

const envios: Envio[] = [];

/**
 * Enrola o transporter que o email.ts criar para anotar o resultado de cada
 * sendMail, sem tocar no produto. `createTransport` é lido na hora do uso, então
 * trocar aqui antes do import funciona.
 */
function instrumentar() {
  const criaTransporte = nodemailer.createTransport.bind(nodemailer);
  nodemailer.createTransport = ((opcoes: unknown) => {
    const transporte = (criaTransporte as (o: unknown) => nodemailer.Transporter)(opcoes);
    const original = transporte.sendMail.bind(transporte);
    transporte.sendMail = (async (mail: Record<string, unknown>) => {
      const info = await original(mail as never);
      envios.push({
        para: String(mail.to),
        assunto: String(mail.subject),
        mail,
        aceita: Array.isArray(info.accepted) && info.accepted.length > 0,
        respostaSmtp: String(info.response ?? '').trim(),
      });
      return info;
    }) as typeof transporte.sendMail;
    return transporte;
  }) as typeof nodemailer.createTransport;
}

async function provarEntrega(conta: { user: string; pass: string; smtp: { host: string; port: number } }) {
  process.env.NODE_ENV = 'test';
  process.env.SMTP_HOST = conta.smtp.host;
  process.env.SMTP_PORT = String(conta.smtp.port);
  process.env.SMTP_USER = conta.user;
  process.env.SMTP_PASS = conta.pass;
  process.env.EMAIL_FROM = `"PapoCall Teste" <${conta.user}>`;
  process.env.FRONTEND_URL = 'https://papocall.vercel.app';

  instrumentar();
  const { emailService } = await import('../src/utils/email');

  await emailService.sendVerificationEmail(conta.user, 'feps', TOKEN_VERIFICACAO);
  await emailService.sendPasswordResetEmail(conta.user, 'feps', TOKEN_RESET);

  console.log('--- 1. entrega pelo email.ts real, via SMTP do Ethereal ---');
  if (envios.length !== 2) throw new Error(`esperava 2 envios, vieram ${envios.length}`);
  for (const envio of envios) {
    console.log(`  "${envio.assunto}" → aceita=${envio.aceita} | resposta do servidor: ${envio.respostaSmtp}`);
    if (!envio.aceita) throw new Error(`o SMTP não aceitou entregar "${envio.assunto}"`);
  }
}

/**
 * Desmonta os `=?UTF-8?B?…?=` / `=?UTF-8?Q?…?=` que o nodemailer coloca em
 * cabeçalho com acento — "Redefinição de senha" não aparece literal no bytes.
 */
function decodificarCabecalho(bruto: string): string {
  return bruto.replace(/=\?([^?]+)\?([BQq])\?([^?]*)\?=/g, (_, charset, tipo, dados) => {
    const buffer =
      tipo.toUpperCase() === 'B'
        ? Buffer.from(dados, 'base64')
        : Buffer.from(
            dados
              .replace(/_/g, ' ')
              .replace(/=([0-9A-Fa-f]{2})/g, (_m, hex) => String.fromCharCode(parseInt(hex, 16))),
            'binary'
          );
    return buffer.toString('utf8');
  });
}

async function provarConteudo() {
  // streamTransport + buffer devolvem a mensagem completa, sem abrir socket: é o
  // mesmo mail-composer que monta o corpo antes de qualquer conexão SMTP. Os
  // objetos abaixo são os que o produto construiu, capturados na entrega.
  const transporte = nodemailer.createTransport({ streamTransport: true, buffer: true });

  console.log('\n--- 2. conteúdo dos bytes que seriam entregues ---');
  const esperados = [
    { assunto: 'Confirme seu e-mail no PapoCall', token: TOKEN_VERIFICACAO, rota: 'verify-email' },
    { assunto: 'Redefinição de senha no PapoCall', token: TOKEN_RESET, rota: 'reset-password' },
  ];

  for (const esperado of esperados) {
    const envio = envios.find((e) => e.assunto === esperado.assunto);
    if (!envio) throw new Error(`o produto não montou a mensagem "${esperado.assunto}"`);

    const info = await transporte.sendMail(envio.mail as never);
    const bruto = (info.message as Buffer).toString('latin1');
    const cabecalho = decodificarCabecalho(bruto);

    // O corpo costuma vir em base64 ou quoted-printable: decodifica o que vier
    // depois do cabeçalho, para procurar dentro do texto real da mensagem.
    const separador = bruto.search(/\r?\n\r?\n/);
    const corpoCodificado = bruto.slice(separador + 1).replace(/=\r?\n/g, '').replace(/=/g, '');
    let decodificado = '';
    try {
      decodificado = Buffer.from(corpoCodificado, 'base64').toString('utf8');
    } catch {
      decodificado = '';
    }
    const procuravel = `${cabecalho}\n${decodificado}`;

    // O assunto com acento sai em mais de uma encoded-word, com a dobra de
    // linha (CRLF + espaço) no meio: comparado com os espaços dentro, ele nunca
    // bateria. Tira os espaços dos dois lados antes de conferir.
    const semEspacos = (s: string) => s.replace(/\s+/g, '');
    const linhaAssunto = /^Subject:[^\r\n]*(?:\r?\n[ \t][^\r\n]*)*/m.exec(bruto)?.[0] ?? '';

    const temAssunto = semEspacos(cabecalho).includes(semEspacos(esperado.assunto));
    const temRota = procuravel.includes(esperado.rota);
    const temToken = procuravel.includes(esperado.token);
    const temDestino = cabecalho.includes(envio.para);
    console.log(
      `  "${esperado.assunto}" | assunto=${temAssunto} destinatário=${temDestino} rota=${temRota} token=${temToken}`
    );
    if (!temAssunto || !temDestino || !temRota || !temToken) {
      console.log(`  Subject cru: ${JSON.stringify(linhaAssunto)}`);
      throw new Error(`mensagem "${esperado.assunto}" sem conteúdo completo`);
    }
  }
}

async function main() {
  const conta = await nodemailer.createTestAccount();
  console.log(`conta de teste: ${conta.user} @ ${conta.smtp.host}:${conta.smtp.port}\n`);
  await provarEntrega(conta);
  await provarConteudo();
  console.log('\nOK: nodemailer 10 entrega pelo nosso transporte e monta o link com o token.');
}

main().catch((erro) => {
  console.error('\nFALHOU:', erro instanceof Error ? erro.message : erro);
  process.exitCode = 1;
});
