# 05 — Resultados

## Antes e depois

| Dimensão | Antes | Depois |
|---|---|---|
| **Fonte da verdade** | servidor | Git |
| **Trilha de mudança** | nenhuma | commit + revisão + histórico |
| **Auditoria dos 8 hosts** | manual, dias | uma execução, minutos |
| **Artefatos de auditoria** | ~26 fragmentados | 10 consolidados |
| **Baseline de host** | inexistente | playbook reproduzível |
| **Firewall** | doc divergente do estado | matriz YAML + gerador |
| **Incidente** | improviso | playbook em fases + evidências |
| **Runbooks** | nenhum | 6 procedimentos |

## Números

- **8** hosts auditados em uma execução.
- **3** hosts descobertos fora do cluster, apesar de documentados como membros.
- **10** arquivos de relatório, contra ~26 fragmentados — menos arquivo, mais
  informação.
- **5** nós no Swarm, **1** manager.
- **6** runbooks escritos.
- **1** incidente classe D conduzido com playbook.

## O que o trabalho realmente entregou

Não foi "infraestrutura nova". A infraestrutura continuou a mesma. O que mudou foi a
**capacidade de responder perguntas**:

- "Qual a versão de kernel deste host?" — agora tem resposta em um arquivo.
- "Quem liberou esta porta?" — agora tem commit.
- "Este host está igual aos outros?" — agora tem baseline.
- "O que fazemos se o PID 1 travar de novo?" — agora tem playbook.
- "Dá para reconstruir este servidor?" — agora dá.

Esse é o resultado que importa em operação: **reduzir o tempo entre a pergunta e a
resposta confiável**.

## O que ficou de fora (e por quê)

| Pendência | Motivo | Impacto |
|---|---|---|
| Migração para Kubernetes | sem ganho operacional para 8 hosts / 1 time | nenhum no curto prazo |
| SLA formal | empresa pequena, sem contrato de disponibilidade | risco de expectativa, não técnico |
| Causa raiz do incidente | post-mortem com `gdb`/`dbgsym` pendente | prevenção parcial (P1–P3 aplicadas) |
| Gestão de segredos completa | migração exige alteração nas aplicações | segredos ainda parcialmente fora do padrão |
| Controlador GitOps | custo de operar mais um componente | drift manual ainda possível |
| Testes automatizados de firewall | sem ambiente de staging representativo | validação manual com evidência |

Publicar o que **não** foi feito não é modéstia. É a diferença entre um case e um
anúncio.

## Aprendizados

**1. Documentação que não é executável envelhece.**
A matriz de portas era linda e errada. Só passou a valer quando virou YAML que gera
regra.

**2. Auditoria sem baseline é meia auditoria.**
Descobrir divergência é útil; ter um estado de referência para comparar é o que
permite corrigir de forma sistemática.

**3. Automação não substitui julgamento.**
O gerador de firewall imprime comandos. Quem aplica é gente, com janela e rollback.
Automatizar a parte mecânica e manter humana a parte perigosa foi decisão, não
limitação.

**4. O incidente ensinou mais que o projeto.**
Planejamento produz organização. Incidente produz prioridade. As cinco lições que
viraram mudança (P1–P5) não teriam aparecido em nenhum roadmap.

**5. Escopo pequeno e honesto vence escopo grande e vago.**
"GitOps, host descartável e auditoria em 8 servidores" é verificável. "Transformação
digital da infraestrutura" não é.

## Se eu começasse hoje

1. Baseline e inventário no primeiro mês.
2. Matriz de portas na primeira semana — é o maior impacto por hora investida.
3. Um controlador GitOps mínimo desde o início.
4. Post-mortem agendado na mesma semana do incidente.
5. Réplica de serviço crítico antes de qualquer otimização.
