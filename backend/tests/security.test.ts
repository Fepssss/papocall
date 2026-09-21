import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

/**
 * Famílias de credencial que este projeto já usou na LiveKit Cloud.
 *
 * Só o prefixo de 8 caracteres entra aqui de propósito: ele não forja token
 * nenhum, e é o que permite procurar o valor inteiro sem ter que copiá-lo para
 * dentro de um teste — que era exatamente como o `fe394eb` vazar um secret de 43
 * caracteres. Ver `project-secret-exposto-historico` na memória do projeto.
 */
const FAMILIAS_CONHECIDAS = ['APInwQYa', 'APIdzjus', 'MEvhqw63'];

/**
 * A partir daqui um prefixo deixou de ser o prefixo documentado e passou a ser
 * um valor real: as chaves da LiveKit têm 20 e os secrets ~43 caracteres.
 */
const COMPRIMENTO_DE_VALOR = 16;

describe('8. Nenhuma credencial inteira no que está versionado', () => {
  const raizDoRepositorio = path.resolve(__dirname, '..', '..');

  it('nenhum arquivo versionado carrega o valor completo de uma credencial conhecida', () => {
    // `git ls-files` lista o índice, não a história: funciona com checkout rasa,
    // que é o que o CI usa. Uma lista vazia é falha, não sucesso — senão o teste
    // passaria por não ter varrido nada.
    const saida = execFileSync('git', ['ls-files','-z'], { cwd: raizDoRepositorio, encoding: 'utf8' });
    const arquivos = saida.split('\0').filter(Boolean);
    assert.ok(arquivos.length > 100, `esperava varrer os arquivos versionados, vieram ${arquivos.length}`);

    const encontrados: string[] = [];

    for (const relativo of arquivos) {
      const absoluto = path.join(raizDoRepositorio, relativo);
      let conteudo: string;
      try {
        // latin1 porque aqui o que importa é achar ASCII dentro de qualquer
        // arquivo; decodificar UTF-8 de um binário daria erro antes disso.
        conteudo = fs.readFileSync(absoluto, 'latin1');
      } catch {
        continue; // submódulo ausente ou link quebrado: nada a varrer
      }

      conteudo.split('\n').forEach((linha, indice) => {
        for (const bruto of linha.match(/[A-Za-z0-9_-]+/g) ?? []) {
          for (const familia of FAMILIAS_CONHECIDAS) {
            if (bruto.startsWith(familia) && bruto.length >= COMPRIMENTO_DE_VALOR) {
              encontrados.push(`${relativo}:${indice + 1} → família ${familia}… com ${bruto.length} caracteres`);
            }
          }
        }
      });
    }

    assert.deepEqual(
      encontrados,
      [],
      'Um valor de credencial está versionado. O arquivo continua no disco depois ' +
        'do commit, então o que resolve é revogar a credencial no painel da LiveKit ' +
        '— apagar a linha não desfaz o que já foi publicado.'
    );
  });
});


describe('7. Salvaguardas de Seguranca e Sanitizacao de Arquivos de Exemplo', () => {
  const rootExamplePath = path.resolve(__dirname, '../../.env.example');
  const backendExamplePath = path.resolve(__dirname, '../.env.example');

  function calculateShannonEntropy(str: string): number {
    const len = str.length;
    if (len === 0) return 0;
    const freqs: Record<string, number> = {};
    for (const char of str) {
      freqs[char] = (freqs[char] || 0) + 1;
    }
    return Object.values(freqs).reduce((sum, count) => {
      const p = count / len;
      return sum - p * Math.log2(p);
    }, 0);
  }

  it('backend/.env.example nao deve conter chaves ou secrets reais', () => {
    assert.ok(fs.existsSync(backendExamplePath), 'backend/.env.example deve existir');
    const content = fs.readFileSync(backendExamplePath, 'utf-8');

    // Nao pode conter credenciais expostas conhecidas.
    // Só o prefixo de cada uma fica no código: `includes` do prefixo continua
    // detectando o valor completo se ele voltar a ser commitado, sem que o
    // próprio teste volte a publicar o segredo no repositório.
    assert.ok(!content.includes('APInwQYa'), 'Nao pode conter a chave antiga');
    assert.ok(!content.includes('MEvhqw63'), 'Nao pode conter o secret antigo');
    assert.ok(!content.includes('APIdzjus'), 'Nao pode conter a chave nova de producao');

    // Chaves LiveKit devem ser estritamente placeholders
    assert.match(content, /LIVEKIT_API_KEY="your_api_key_here"/);
    assert.match(content, /LIVEKIT_API_SECRET="your_api_secret_here"/);
    assert.match(content, /LIVEKIT_URL="wss:\/\/seu-projeto\.livekit\.cloud"/);

    // Verifica entropia de valores atribuidos
    const lines = content.split('\n');
    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith('#')) continue;
      const [key, ...valParts] = trimmed.split('=');
      const val = valParts.join('=').replace(/^["']|["']$/g, '').trim();

      // Ignora chaves vazias ou placeholders explicitos
      if (!val || val === 'development' || val.includes('localhost') || val.includes('seu-projeto') || val.startsWith('your_')) {
        continue;
      }

      // Se o valor for longo (> 20 chars), a entropia nao deve parecer uma chave criptografica real (> 4.5)
      if (val.length > 20) {
        const entropy = calculateShannonEntropy(val);
        assert.ok(entropy < 4.5, `Chave ${key} em .env.example possui entropia suspeita: ${entropy.toFixed(2)}`);
      }
    }
  });

  it('root .env.example deve conter apenas placeholders', () => {
    assert.ok(fs.existsSync(rootExamplePath), 'root .env.example deve existir');
    const content = fs.readFileSync(rootExamplePath, 'utf-8');

    assert.ok(!content.includes('APInwQYa'));
    assert.ok(!content.includes('MEvhqw63'));
    assert.ok(!content.includes('APIdzjus'));
    assert.match(content, /LIVEKIT_API_KEY=your_api_key_here/);
    assert.match(content, /LIVEKIT_API_SECRET=your_api_secret_here/);
  });
});
