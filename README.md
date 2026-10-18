# PbW Code Engine

Utilitário de manutenção para macOS: livre, open source (GPL-3.0), sem conta, sem login, sem telemetria.

## O que faz (v0.1)
- **Varredura**: caches, logs, DerivedData, caches de npm/Gradle/Cargo e .dmg antigos. Mostra o motivo de cada item.
- **Mapa**: uso de disco (somente leitura).
- **Duplicatas**: por conteúdo (SHA-256); sempre mantém ao menos uma cópia.
- **Apps**: desinstala com os arquivos relacionados (apps da Apple não são listados).
- **Inicialização**: desativa agentes de `~/Library/LaunchAgents`.
- **Quarentena**: nada é apagado direto; tudo fica 30 dias e pode ser restaurado.
- **Relatório**: histórico local de ações.

## Segurança
Toda ação passa por `SafetyGuard` (`Sources/CodeEngineCore/SafetyGuard.swift`): sistema, pasta pessoal, chaves, iCloud Drive, bibliotecas do Fotos/Música e symlinks para áreas protegidas são sempre bloqueados.

## Compilar
```
swift run CoreChecks        # verificações de segurança do núcleo
./scripts/build-app.sh      # gera dist/PbW Code Engine.app (~2 MB, limite: 100 MB)
```
Sem conta Apple: o app é assinado ad-hoc. Na primeira abertura, use clique direito → Abrir.

## Roadmap
- v1.1: aba **Túnel** (gerenciador de configurações WireGuard com lista de nós EUA/China/Espanha/Portugal mantida pela comunidade). O projeto não hospeda servidores.
