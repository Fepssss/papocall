import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

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

    // Nao pode conter credenciais expostas conhecidas
    assert.ok(!content.includes('APInwQYax6X6V9Y'), 'Nao pode conter a chave antiga APInwQYax6X6V9Y');
    assert.ok(!content.includes('MEvhqw634u8yUnYflJVMCrc8eKGQUrH1LbUj7wtpKt5'), 'Nao pode conter o secret antigo');
    assert.ok(!content.includes('APIdzjusbH2TnW4'), 'Nao pode conter a chave nova de producao');

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

    assert.ok(!content.includes('APInwQYax6X6V9Y'));
    assert.ok(!content.includes('MEvhqw634u8yUnYflJVMCrc8eKGQUrH1LbUj7wtpKt5'));
    assert.ok(!content.includes('APIdzjusbH2TnW4'));
    assert.match(content, /LIVEKIT_API_KEY=your_api_key_here/);
    assert.match(content, /LIVEKIT_API_SECRET=your_api_secret_here/);
  });
});
