---
trigger: always_on
description: Regras obrigatórias de desenvolvimento e versionamento do PapoCall
---

# Regras do Projeto PapoCall

1. **Idioma**: Sempre responder em Português do Brasil (pt-BR).
2. **Nome do Produto**: Exclusivamente **PapoCall** (proibido usar nomes legados ou concorrentes).
3. **Padrão de Versionamento**:
   - Versão base atual: `1.0.0c`.
   - Mudanças pequenas/patches: `1.0.0d`, `1.0.0e`, ..., até `1.0.0z`.
   - Ao estourar `z`: vira `1.0.1a`, ..., até `1.0.1z`, depois `1.0.2a`.
   - Big Updates: `2.0.0a`.
   - Sempre sincronizar: `HudTheme.appVersion`, `pubspec.yaml`, `setup.iss`, `package.json` e `build_installer.ps1`.
4. **Git Author para Vercel**:
   - Commits devem usar `user.name = "Feps"` e `user.email = "fepsmiotti@gmail.com"` para manter compatibilidade com a verificação de assento da Vercel.
5. **Estética Visual**:
   - Respeitar sempre as diretrizes de `HudTheme`: fundo escuro tático, bordas finas sutis, tipografia monoespaçada/clean e destaques em verde esmeralda (#22C55E).
6. **Atualização do Instalador e do Site (Mandatório)**:
   - Ao final de cada atualização, sem exceção:
     - Executar `installer/build_installer.ps1` para gerar o novo `PapoCall-Setup.exe`.
     - Fazer commit e push na branch `main` com autor `Feps <fepsmiotti@gmail.com>` para atualizar o instalador no site e na Vercel (`https://papocall.vercel.app`).
