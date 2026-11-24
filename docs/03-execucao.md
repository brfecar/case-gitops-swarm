# 03 — Execução

Três frentes: auditoria, firewall e runbooks. Todas com o mesmo princípio — o
resultado tem que ser reproduzível, não narrado.

---

## 1. Auditoria com Ansible

**Objetivo:** levantar os 8 hosts em uma única execução e produzir um artefato
objetivo por máquina.

**Antes:** ~26 arquivos fragmentados, gerados por playbooks diferentes, em momentos
diferentes.

**Depois:** 10 arquivos.

| Arquivo | Conteúdo |
|---|---|
| `servidor-<host>.txt` × 8 | SO, hardware, rede, disco, pacotes, Docker, containers, redes, volumes, imagens, papel no Swarm |
| `swarm-topologia.txt` | nós, serviços, tasks, stacks, redes overlay, secrets, configs, hosts fora do cluster |
| `RELATORIO-CONSOLIDADO.txt` | sumário final |

### O que o playbook mestre coleta

**Play 1 — todos os hosts**

| Coleta | Dado | Seção |
|---|---|---|
| `setup` | SO, kernel, hardware, rede, disco | `[SO]`, `[HARDWARE]`, `[REDE]`, `[DISCO]` |
| `package_facts` | pacotes com versão | `[PACOTES]` |
| `docker info` | versão, driver, root, cgroup | `[DOCKER]` |
| `docker ps -a` | containers locais | `[CONTAINERS]` |
| `docker network/volume/image ls` | redes, volumes, imagens | `[REDES]`, `[VOLUMES]`, `[IMAGENS]` |
| `set_fact` | classificação do Swarm | `[SWARM]` |

**Play 2 — somente o manager**

| Comando | Dado |
|---|---|
| `docker node ls` | nós do cluster |
| `docker service ls` / `ps` | serviços e onde cada task roda |
| `docker stack ls` | stacks |
| `docker network ls --filter scope=swarm` | redes overlay |
| `docker secret ls` / `config ls` | secrets e configs |
| `hostvars[*].swarm_estado` | hosts fora do cluster |

### Classificação automática do papel

Cada host é classificado por fatos, não por convenção:

| Condição | Estado |
|---|---|
| `LocalNodeState == active` e `ControlAvailable == true` | **manager** |
| `LocalNodeState == active` | **worker** |
| Docker presente, Swarm `inactive` | **standalone** — fora do cluster |
| Docker ausente | **sem docker** |

Foi essa lógica que revelou que **três hosts não pertenciam ao Swarm**, apesar de
estarem documentados como se pertencessem. Sem classificação automática, a
divergência continuaria invisível.

### Armadilhas reais (e como foram resolvidas)

1. **Jinja2 × Go template.** Os formatos do Docker usam `{{ }}`, que colide com
   Jinja2. Solução: escape explícito — `'{{ '{{' }}.Names}}'`.
2. **`docker stack ls --format .Orchestrator`.** Campo não existe em CLIs antigas.
   Solução: usar apenas `.Name` e `.Services`.
3. **`docker network ls --scope swarm`.** A flag não existe. Solução:
   `--filter scope=swarm`.
4. **Scalar dobrado (`>-`) em `set_fact`.** Introduzia espaço no fim da string;
   `manager ` ≠ `manager` fazia todo manager cair em "standalone". Solução:
   expressão `ternary` em linha única.
5. **Emoji em `sed`.** `sed 's/^[✅⚠️❌] //p'` não casa com emoji multibyte.
   Solução: classificar por palavra-chave com `grep`.

Essas cinco linhas valem mais que o playbook inteiro: são o que separa "escrevi um
YAML" de "rodei em produção e fiz funcionar".

### Execução

```bash
cd ansible
ansible all -m ping
ansible-playbook playbooks/00-auditoria.yml
```

O playbook mestre **precisa** rodar antes do consolidado: os passos seguintes apenas
leem os `servidor-*.txt` gerados. Rodar só o consolidado reaproveita dados velhos —
e relatório velho é pior que relatório nenhum, porque parece atual.

---

## 2. Firewall como código

### O método de auditoria

Nenhuma regra foi declarada "aberta" ou "fechada" sem evidência:

```bash
# existe listener real?
ss -tulnp | grep ':<PORTA>'

# a regra existe e com qual contador?
sudo ufw status numbered | grep <PORTA>
iptables -L ufw-user-forward -v -n | grep <PORTA>
iptables -L ufw-user-input -v -n | grep <PORTA>

# a regra do Docker respeita o UFW?
iptables -S DOCKER-USER | grep ufw-docker
```

Para UDP, **contador é a fonte da verdade**. Um probe externo não prova recepção —
só prova que o pacote saiu.

### O que a matriz expôs

- Regra órfã: porta liberada, sem listener, com tráfego residual.
- Serviço de banco exposto publicamente além do necessário.
- Métricas internas publicadas em porta pública, sem autenticação.
- Divergência entre a documentação e o estado real em dois hosts.
- Host legado com firewall inativo e portas antigas abertas.

### O gerador

A matriz é a fonte; o gerador é descartável. `firewall/render_ufw.py` lê o YAML e
**imprime** os comandos. Ele não executa nada — a aplicação é decisão humana, com
janela e rollback.

```bash
python3 firewall/render_ufw.py firewall/portas.example.yml
```

Por que não aplicar automaticamente: firewall é a categoria de mudança em que um
erro custa mais caro. Automatizar a **geração** elimina erro de digitação;
automatizar a **aplicação** adiciona um risco que o time não tinha estrutura para
absorver.

---

## 3. Runbooks

Escritos **antes** do próximo incidente, não depois:

| Runbook | Pergunta que responde |
|---|---|
| Deploy e rollback | como subir e como voltar atrás sem pânico |
| Firewall | como liberar, restringir e reverter uma regra |
| Backup e restore | como restaurar de verdade (não só "o backup rodou") |
| Observabilidade | onde olhar quando o alerta dispara |
| Switchover de PostgreSQL | como promover a réplica com segurança |
| Resposta a incidente | quem faz o quê, na ordem, com evidência preservada |

O valor de um runbook não é a execução perfeita. É **reduzir o número de decisões
tomadas sob estresse**.

---

## 4. O ciclo de mudança

Toda alteração seguia a mesma sequência:

1. **Escrever no Git** — stack, regra ou playbook.
2. **Classificar o risco** — classe A (sem impacto) a D (exige janela e aval).
3. **Revisar** — outra pessoa lê o diff.
4. **Executar** — com rollback definido antes.
5. **Verificar** — logs, métricas, estado do cluster.
6. **Atualizar a documentação no mesmo commit.**

O passo 6 é o que evita a documentação envelhecer. Se a doc só é atualizada
"depois", ela nunca é.
