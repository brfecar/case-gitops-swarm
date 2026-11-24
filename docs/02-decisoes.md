# 02 — Decisões de arquitetura

Cinco decisões estruturaram o trabalho. Para cada uma: o problema, a escolha, o que
foi descartado e o preço pago.

---

## D1 — Git como fonte da verdade

**Problema:** a configuração real vivia no servidor. O repositório descrevia uma
intenção que ninguém garantia.

**Decisão:** stack, firewall, baseline e runbooks passam a viver no Git. O servidor
executa; não é mais o lugar onde a mudança nasce.

```
Repositório Git  ──►  docker stack deploy / ansible-playbook  ──►  Servidor
     │                                                              │
     └── histórico, revisão, rollback                    só executa o que veio do Git
```

**O que mudou na prática:**

- Toda alteração de stack é um `docker-compose.yml` versionado, não um
  `docker service update` digitado.
- Toda regra de firewall nasce de um YAML revisável, não de um `ufw allow` avulso.
- Rollback é `git revert` + deploy, não arqueologia de shell history.

**Honestidade:** isso é GitOps no **processo**, não na ferramenta. Não havia
controlador reconciliando estado (Argo CD, Flux). O deploy era disparado a partir
do repositório, mas um `docker service update` manual ainda era tecnicamente
possível. A regra era cultural e revisada em code review — não imposta pelo
ambiente.

**Trade-off aceito:** um controlador de verdade exigiria mais um componente para
operar. Com 8 hosts e um time pequeno, o ganho não pagava o custo.

---

## D2 — Host descartável em vez de KVM

**Problema:** cada host acumulava anos de ajustes. Reconstruir era inviável;
consertar era a única opção.

**Decisão:** containers no bare metal, com baseline reproduzível via Ansible.
KVM/virtualização **não** é a regra geral.

A comparação usou três critérios do time: manutenção rápida, migração fácil e
capacidade de aguentar carga alta.

| Critério | Containers no bare metal | KVM (VM por host) |
|---|---|---|
| **Manutenção** | 1 kernel por host → patcheia 1 SO | 1 kernel do host + 1 por VM → multiplica SOs |
| **Migração** | `ansible-playbook` + `docker stack deploy` no nó novo = minutos | copiar imagem qcow2 (GB) + reconfigurar rede |
| **Carga alta (recepção UDP)** | melhor latência, sem overhead, `network_mode: host` | virtio adiciona CPU/IRQ; ~300–500 MB de memória por kernel de VM |
| **Isolamento** | namespace + seccomp (suficiente para single-tenant) | mais forte (hipervisor) — necessário em multi-tenant |
| **Reparo de host quebrado** | **descarta e reconstrói** com o playbook | conserta a VM; o host físico ainda precisa ser reparado |

**Modelo-alvo:**

```
Bare metal (mínimo): SO LTS + SSH + Docker/Swarm + agente de métricas
        │
        └─ Docker Swarm (1 manager + N workers)
             └─ stacks versionadas no Git
                  ├─ recepção        → network_mode: host
                  ├─ plataforma      → Kafka, PostgreSQL, observabilidade
                  └─ web             → proxy reverso, aplicações
```

**Princípio:** segurança não vem de "nunca tocar no host". Vem de poder
**reconstruir em minutos**. Host estragado é *replace*, não *repair*.

**Onde KVM ainda se justifica:** SO legado que precisa ser isolado, serviço que
exige kernel ou módulo próprio, e isolamento forte por exigência de multi-tenant.

**Trade-off aceito:** isolamento mais fraco que hipervisor. Para ambiente
single-tenant com aplicações confiáveis, foi considerado aceitável — e explícito no
documento de decisão.

---

## D3 — Docker Swarm, não Kubernetes

**Problema:** o cluster era Swarm. Surgiu a pergunta natural: migrar?

**Decisão:** não migrar.

| Fator | Swarm | Kubernetes |
|---|---|---|
| Operação | um binário, parte do Docker | control plane, etcd, CNI, ingress, operadores |
| Curva do time | já dominada | alta, e o time era pequeno |
| Necessidade real | réplicas, service discovery, secrets, deploy declarativo | o mesmo, com ecossistema muito maior |
| Custo de migração | zero | meses, com risco em serviço de produção |
| Ganho | — | ecossistema, padronização de mercado, operadores |

**Racional:** Kubernetes resolve problemas que o ambiente não tinha — multi-tenancy
complexa, dezenas de times, autoscaling agressivo. Migrar seria trocar um problema
conhecido por um desconhecido, em produção, sem ganho operacional claro.

**O que se perde:** ecossistema, operadores prontos, ferramentas de mercado e
"currículo". Isso foi assumido como custo consciente.

**Se o ambiente crescesse:** o gatilho de migração seria número de times, não número
de hosts. Com um time e um cluster, Swarm basta.

---

## D4 — Ansible em vez de agente

**Problema:** auditar 8 hosts sem instalar nada neles.

| Critério | Ansible | Inventário com agente (OCS/GLPI/Wazuh) |
|---|---|---|
| Instala algo no servidor? | não, só SSH | sim, agente + servidor central |
| Tempo até o primeiro resultado | minutos | horas ou dias |
| Custo | zero (GPLv3) | infraestrutura extra para manter |
| Coleta topologia do Swarm | sim, a partir do manager | sim |
| Histórico visual | não nativo | sim (dashboard) |

**Decisão:** Ansible, pela velocidade e por não adicionar componente.

O detalhe que fez diferença: como o manager do Swarm enxerga todos os nós, a
topologia completa do cluster é coletada **a partir de um único host** — os workers
não precisam ser acessados individualmente para isso.

**Trade-off aceito:** sem dashboard. A compensação foi versionar os relatórios no
Git, o que dá histórico auditável — diferente de um dashboard que mostra só o agora.

---

## D5 — Matriz de portas como código

**Problema:** a matriz de portas era um documento; o firewall era um estado. Os dois
divergiam.

**Decisão:** a matriz vira YAML versionado e um gerador produz as regras `ufw`.

```yaml
- porta: 5001
  proto: tcp
  servico: gateway-exemplo
  origem: any
  acao: allow
```

**Regra de revisão:** toda porta publicada precisa de uma linha correspondente na
matriz **ou** justificativa documentada no mesmo commit. Mudou a porta, mudou o YAML.

**Por que isso importa mais do que parece:** o firewall é o lugar onde a
documentação envelhece mais rápido. Uma regra órfã esquecida é superfície de ataque
silenciosa. Tornar a matriz a fonte da verdade transforma "eu acho que está aberto"
em "está escrito, revisado e versionado".

---

## O que eu faria diferente

1. **Baseline antes da auditoria.** Auditar primeiro revelou divergências, mas
   metade do valor veio de já ter um baseline para comparar. A ordem ideal é
   baseline → auditoria → correção.
2. **Matriz de portas desde o dia 1.** Foi a entrega com melhor relação
   esforço/impacto e chegou no meio do caminho.
3. **Controlador GitOps desde o início.** Mesmo um Argo CD pequeno teria eliminado
   a possibilidade de drift manual. O processo funcionou; a ferramenta teria
   garantido.
4. **Post-mortem agendado no mesmo dia do incidente.** Evidência preservada sem
   análise vira arquivo morto.
