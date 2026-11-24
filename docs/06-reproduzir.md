# 06 — Reproduzir em laboratório

Este documento permite ver o fluxo funcionando sem precisar de infraestrutura real.
Três VMs (ou três containers com systemd, se você já tem prática) bastam.

Tempo estimado: 40 minutos.

---

## Requisitos

| Item | Versão mínima |
|---|---|
| Ansible (na máquina de controle) | 2.14 |
| Docker Engine | 24.x |
| Três hosts Linux acessíveis por SSH | Debian/Ubuntu ou RHEL-like |
| Chave SSH sem senha para os três | — |

Neste laboratório os hosts são `br-01`, `br-02` e `br-03`, com IPs `192.0.2.10` a
`192.0.2.12`. A faixa `192.0.2.0/24` é reservada para documentação (RFC 5737);
troque pelos endereços das suas VMs.

---

## 1. Preparar o inventário

```bash
cp ansible/inventory.example.ini ansible/inventory.ini
```

No `inventory.ini`, mantenha apenas o grupo `[br]` com os três hosts e o grupo
`[swarm_manager]` apontando para `br-01`. Comente os grupos `[us]` e `[eu]` — o
playbook de auditoria roda em `servers` e o de topologia somente no manager.
O arquivo está no `.gitignore` de propósito: nunca versione inventário com endereço real.

Teste a conexão:

```bash
cd ansible
ansible all -i inventory.ini -m ping
```

Saída esperada: `pong` nos três hosts. Se falhar, o problema é SSH/chave, não Ansible.

---

## 2. Rodar a auditoria

```bash
ansible-playbook -i inventory.ini playbooks/00-auditoria.yml
```

O relatório aparece em `ansible/relatorios/`, um arquivo por host. Rode duas vezes
alterando algo (instale um pacote em um nó) e compare: é assim que o playbook vira
ferramenta de detecção de desvio, não só de inventário.

---

## 3. Subir o cluster

No `br-01`:

```bash
docker swarm init --advertise-addr <IP_DO_BR_01>
```

Copie o comando `docker swarm join` que ele imprime e rode nos outros dois.

Confirme:

```bash
docker node ls
```

Esperado: um manager e dois workers, todos `Ready`.

---

## 4. Subir a stack versionada

O compose declara um secret externo. Crie-o no manager antes do deploy:

```bash
printf 'valor-de-teste' | docker secret create app_token -
docker stack deploy -c stacks/exemplo-app/docker-compose.yml exemplo
```

Verifique:

```bash
docker stack services exemplo
docker service ps exemplo_web
```

O padrão a observar: **você não entrou em nenhum servidor para criar container**. Tudo
veio do arquivo versionado. Esse é o ponto do exercício.

---

## 5. Simular uma mudança

Altere o número de réplicas do serviço `web` em
`stacks/exemplo-app/docker-compose.yml`, faça commit e suba de novo:

```bash
git commit -am "chore: escala web para 3 replicas"
docker stack deploy -c stacks/exemplo-app/docker-compose.yml exemplo
```

Depois:

```bash
git log --oneline -- stacks/exemplo-app/docker-compose.yml
```

A pergunta "quem mudou e por quê" tem resposta. É isso que faltava no cenário original.

---

## 6. Simular o incidente (opcional, e com cuidado)

**Não faça isso em máquina que você usa.** O objetivo é entender por que PID 1 travado é
diferente de serviço travado.

Em uma VM descartável:

```bash
# deixe o host sem resposta a novos forks (efeito colateral sério)
sudo bash -c 'echo 1 > /proc/sys/kernel/sysrq'
```

O ponto pedagógico não é reproduzir o SIGABRT — é observar que:

- `systemctl` para de responder;
- `reboot` não funciona;
- o nó continua no cluster até o timeout de heartbeat.

Depois disso, `drain` no manager é a única mitigação limpa, exatamente como descrito em
[`04-incidente.md`](04-incidente.md).

---

## Limpeza

```bash
docker stack rm exemplo
docker secret rm app_token
docker swarm leave --force   # em cada nó
```

---

## O que este laboratório não reproduz

- latência real entre regiões;
- acesso por console/KVM (a parte que mais dói no incidente real);
- volume de dados de produção;
- Kafka e PostgreSQL com carga.

O que ele reproduz é o essencial: **Git como origem, host descartável, auditoria
repetível**.
