# Case GitOps — nuvem privada em 8 servidores

> **Estudo de caso sanitizado.** Este repositório documenta uma operação real de
> infraestrutura sem expor cliente, provedor, hostnames, IPs, domínios ou portas de
> produção. Ver [NOTICE.md](NOTICE.md).

Oito servidores em três regiões. Docker Swarm. Recepção de telemetria, filas Kafka,
PostgreSQL, observabilidade e aplicações web. Tudo configurado à mão, host por host,
durante anos.

Este é o registro de como isso passou a ser versionado, auditável e reconstruível.

---

## O problema

O ambiente funcionava. O problema não era disponibilidade — era **confiança**.

- **Sem trilha de mudança.** Uma porta liberada no firewall não deixava rastro de
  quem liberou, quando ou por quê.
- **Host que não reproduzia.** Dois servidores "iguais" tinham pacotes, kernels e
  regras diferentes. Não havia baseline.
- **Incidente sem runbook.** Quando um nó travou de verdade, o diagnóstico começou
  do zero, às pressas.
- **Documentação que envelhecia.** A matriz de portas descrevia um estado que já
  não era o real.

Regra que passou a valer: **se não está no Git, não existe.** O servidor executa;
ele não é a fonte da verdade.

---

## A decisão

| Decisão | Por quê |
|---|---|
| **Git como fonte da verdade** | Stack, firewall e baseline saem do host e passam a viver no repositório, com histórico e revisão. |
| **Host descartável** | No bare metal fica só SO, SSH, Docker e agente de métricas. O resto é container versionado. Host quebrado se **substitui**, não se conserta. |
| **Ansible agentless** | Inventário e auditoria dos 8 hosts em uma execução, sem instalar agente. |
| **Docker Swarm, não Kubernetes** | O cluster já existia, o time era pequeno e o ganho de migrar não pagava o custo. Decisão consciente, não falta de opção. |
| **Matriz de portas versionada** | Regra de firewall deixa de ser memória de quem executou e passa a ser configuração revisável. |

O detalhamento — incluindo o que foi descartado e por quê — está em
[docs/02-decisoes.md](docs/02-decisoes.md).

---

## A execução

1. **Inventário auditável.** Um playbook mestre coleta sistema, hardware, rede,
   disco, pacotes, Docker, containers, volumes, imagens e topologia do Swarm.
   Resultado: 10 arquivos objetivos (8 hosts + topologia + consolidado), no lugar de
   ~26 relatórios fragmentados feitos à mão.

2. **Baseline e host descartável.** Todo nó nasce do mesmo playbook: SO mínimo,
   SSH, Docker, agente. Reconstruir um host deixa de ser um projeto e passa a ser
   uma tarefa de minutos.

3. **Firewall como código.** A matriz de portas virou YAML versionado e um gerador
   produz as regras `ufw`. Mudou a regra, mudou no Git — no mesmo commit.

4. **Runbooks escritos antes do próximo incidente.** Deploy/rollback, firewall,
   backup/restore, observabilidade, switchover de banco e resposta a incidente.

5. **Um incidente real, documentado.** Um nó ficou com o `systemd` PID 1 congelado
   por `SIGABRT`. O recovery virou playbook em fases e virou post-mortem:
   [docs/04-incidente.md](docs/04-incidente.md).

---

## O resultado

| Antes | Depois |
|---|---|
| Configuração só no servidor | Configuração no Git, com histórico |
| Auditoria manual, dias | Uma execução, minutos |
| ~26 relatórios fragmentados | 10 relatórios consolidados |
| Firewall divergente da doc | Matriz versionada + gerador de regras |
| Incidente sem procedimento | Playbook em fases + evidências preservadas |
| "Host igual" sem prova | Baseline único e reproduzível |

Números e limites reais estão em [docs/05-resultados.md](docs/05-resultados.md).

---

## O que **não** foi feito

Portfólio sem escopo delimitado é propaganda. Ficou de fora:

- **Migração para Kubernetes.** Swarm atendia; migrar seria trocar um problema
  conhecido por um desconhecido.
- **SLA formal.** Não havia contrato de disponibilidade — havia boa vontade e
  plantão informal.
- **Causa raiz do incidente.** O core dump foi preservado, mas o post-mortem com
  `gdb` e `dbgsym` ficou pendente.
- **Gestão de segredos completa.** O destino era Docker Secrets + Ansible Vault;
  a migração ficou parcial.
- **Pipeline GitOps completo.** O deploy era disparado a partir do repositório, mas
  sem um controlador (Argo CD/Flux) reconciliando estado. GitOps na prática, não na
  ferramenta.

---

## Estrutura

```
case-gitops-swarm/
├── README.md                     ← você está aqui
├── NOTICE.md                     ← o que foi sanitizado e por quê
├── docs/
│   ├── 01-contexto.md            ← cenário, restrições, o que existia
│   ├── 02-decisoes.md            ← GitOps, host descartável, Swarm × K8s
│   ├── 03-execucao.md            ← auditoria, matriz de portas, armadilhas
│   ├── 04-incidente.md           ← PID 1 congelado (caso real, sanitizado)
│   ├── 05-resultados.md          ← antes/depois, pendências, aprendizados
│   └── 06-reproduzir.md          ← laboratório em 3 VMs (~40 min)
├── diagrams/
│   ├── topologia.mmd             ← Mermaid (renderiza no GitHub)
│   └── fluxo-gitops.mmd
├── ansible/
│   ├── ansible.cfg
│   ├── inventory.example.ini     ← placeholders, nunca o inventário real
│   └── playbooks/
│       ├── 00-auditoria.yml
│       └── 10-recovery.yml
├── stacks/
│   └── exemplo-app/docker-compose.yml
├── firewall/
│   ├── portas.example.yml
│   ├── render_ufw.py             ← matriz YAML → comandos ufw
│   └── requirements.txt          ← PyYAML (única dependência)
└── scripts/
    └── check-sensitive.ps1       ← checklist de sanitização
```

---

## Como ler este repositório

Se você tem 5 minutos: este README e [docs/04-incidente.md](docs/04-incidente.md).

Se você quer a parte técnica: [docs/02-decisoes.md](docs/02-decisoes.md) e
[docs/03-execucao.md](docs/03-execucao.md), depois os playbooks em `ansible/`.

Se você quer avaliar o resultado: [docs/05-resultados.md](docs/05-resultados.md).

Se você quer colocar a mão: [docs/06-reproduzir.md](docs/06-reproduzir.md) — laboratório em 3 VMs (~40 min).

---

## Reproduzindo o padrão

Este repositório **não** é executável contra a infraestrutura original. Os exemplos
usam IPs de documentação (RFC 5737) e nomes genéricos:

```bash
cd ansible
cp inventory.example.ini inventory.ini   # ajuste os hosts
ansible all -m ping
ansible-playbook playbooks/00-auditoria.yml
```

O gerador de firewall apenas **imprime** comandos; ele não altera nada. A única
dependência é PyYAML:

```bash
python -m pip install -r firewall/requirements.txt
python firewall/render_ufw.py firewall/portas.example.yml --check
python firewall/render_ufw.py firewall/portas.example.yml
```

O passo a passo completo — Swarm, stack de exemplo, mudança versionada e simulação
de incidente em 3 VMs — está em [docs/06-reproduzir.md](docs/06-reproduzir.md).

---

## Licença

MIT — ver [LICENSE](LICENSE). O conteúdo é documentação e exemplo; a infraestrutura
descrita não é pública.
