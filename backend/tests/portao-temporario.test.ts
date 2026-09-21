import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

// Arquivo temporário de um único commit, apagado no commit seguinte do mesmo PR.
// Serve para provar que o portão de CI bloqueia merge com teste vermelho.
describe('Verificação do portão de CI', () => {
  it('falha de propósito', () => {
    assert.equal(1 + 1, 3);
  });
});
