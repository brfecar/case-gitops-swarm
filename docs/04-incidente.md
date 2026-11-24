# 04 — Incidente: PID 1 congelado

> Caso real, sanitizado. Nome do host, do provedor e identificadores internos foram
> removidos. O que ficou é o que importa: a sequência de decisões.

## Resumo

Um nó worker do Swarm ficou com o **`systemd` PID 1 congelado por `SIGABRT`**.

`systemctl reboot` não funciona quando o PID 1 está travado — não há processo para
processar o pedido. O nó continuava listado no cluster como `Ready`, e o scheduler
entrava em *retry storm* tentando alocar tasks que não conseguiam subir.

Mitigação: **drain do nó** no manager + **preservação do core dump** antes de
qualquer reboot. O recovery físico foi delegado ao provedor de infraestrutura.

**Classe D** no processo de change management: exige janela aprovada e aval.

---

## Impacto

| Item | Efeito |
|---|---|
| Serviços do nó | hubs e gateways com réplica única pararam; serviço de alertas e stack de logs fora |
| Cluster | worker em drain → tasks redistribuídas ou paradas; manager intacto |
| Telemetria | recepção afetada nas portas atendidas por aquele nó |
| Dados | sem perda confirmada; filas absorveram a interrupção |

O detalhe que dói: **réplica única**. Serviços que só existiam naquele nó não tinham
para onde ir. O drain protegeu o cluster, não o serviço.

---

## Linha do tempo

| Momento | Evento |
|---|---|
| T0 | `systemd` PID 1 congela com `SIGABRT`; core dump gravado em `/core` |
| T0 + diagnóstico | diagnóstico **read-only**: nada é reiniciado antes de preservar evidência |
| T0 + decisão | plano de recovery em fases, classe D, rollback definido |
| T1 | drain aplicado no manager — encerra o retry storm |
| T1 + evidência | core dump e journal exportados para fora do host |
| T2 | recovery físico delegado ao provedor (console/KVM + reboot) |
| T3 | validação: `systemd` `running`, nó `active`, réplicas `1/1`, porta do serviço de alertas aberta |

---

## O que foi feito certo

### 1. Diagnóstico sem pressa antes de agir

A tentação era reiniciar. Reiniciar apagaria a evidência e não resolveria — com PID 1
congelado, o reboot nem acontece.

O primeiro passo foi **ler sem tocar**: estado do nó, `journalctl`, core dump. A
regra "preservar antes de reiniciar" salvou o único artefato que permitiria
post-mortem.

### 2. Drain em vez de reinício

`docker node update --availability drain <node>` resolveu o sintoma imediato sem
tocar no host travado:

- o scheduler parou de tentar alocar tasks naquele nó;
- os demais nós continuaram operando;
- o host ficou isolado, não derrubado.

### 3. Recovery em fases, nunca tudo de uma vez

O playbook foi escrito com tags independentes e ordem obrigatória:

```
evidencia → drain → reboot → wait → update? → crashreboot → active → valida
```

Nenhuma fase roda por acidente: todas usam `tags: [never]` e exigem seleção
explícita. A fase de `update` é *opt-in* — só com escopo aprovado em janela.

### 4. Delegação consciente

Com PID 1 congelado, o reboot exige console/KVM. Isso é acesso físico — competência
do provedor. Insistir em resolver internamente seria teatro de autonomia. A
delegação foi registrada com escopo, data e o que precisava ser validado no retorno.

---

## O que foi feito errado (ou poderia ser melhor)

- **Réplica única em serviço crítico.** O cluster tinha 5 nós, mas o serviço existia
  em um só. Alta disponibilidade de infraestrutura não é alta disponibilidade de
  serviço.
- **Post-mortem não concluído.** O core dump foi preservado, mas a análise com
  `gdb` + `dbgsym` do `systemd` e do kernel da época ficou pendente. Evidência sem
  análise não vira aprendizado.
- **Kernel antigo.** Havia suspeita de kernel antigo + userspace instável. O upgrade
  ficou como prevenção, não como correção imediata.

---

## Lições que viraram mudança

| # | Lição | Ação |
|---|---|---|
| P1 | PID 1 crashado não reinicia sozinho por padrão | `CrashReboot=yes` em `/etc/systemd/system.conf` (classe B) — evita KVM manual no próximo caso |
| P2 | Réplica única é ponto único de falha | replicar imagens críticas entre nós |
| P3 | Kernel antigo é risco acumulado | upgrade de kernel, com o antigo mantido como fallback no GRUB |
| P4 | `systemctl reboot` não é opção com PID 1 congelado | documentar Magic SysRq (`s` → `u` → `b`) e o caminho de console do provedor |
| P5 | Métricas de serviço binário não se testam com `curl` | validação por `nc -vz` (conexão TCP), nunca HTTP |

A lição P5 parece pequena e evitou um falso negativo: o serviço de alertas usa
protocolo binário próprio. Um `curl` retornaria erro mesmo com o serviço saudável.

---

## Como o playbook ficou

`ansible/playbooks/10-recovery.yml` implementa as fases. Dois princípios de design:

1. **Nada destrutivo sem tag explícita.** `never` em todas as fases.
2. **Validação objetiva no fim.** `systemctl is-system-running` = `running`, nó
   `active` no cluster, réplicas `1/1`, porta respondendo.

```bash
ansible-playbook playbooks/10-recovery.yml -e target_host=us-02 --tags evidencia
ansible-playbook playbooks/10-recovery.yml --tags drain
ansible-playbook playbooks/10-recovery.yml -e target_host=us-02 --tags reboot
ansible-playbook playbooks/10-recovery.yml --tags valida
```

O que este incidente ensinou sobre operação, mais do que sobre Linux:

> **Em incidente, a primeira ação é impedir que a situação piore — e a segunda é
> garantir que você vai conseguir entender o que aconteceu. Reiniciar não é
> diagnosticar.**
