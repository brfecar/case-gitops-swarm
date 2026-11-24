# Nota de sanitização

Este repositório é um **estudo de caso**. Ele foi derivado de documentação interna
real, mas nenhum dado que permita localizar, acessar ou atacar a infraestrutura
original foi publicado.

## O que foi removido ou substituído

| Dado original | O que aparece aqui |
|---|---|
| Nome do cliente e da empresa | "empresa de telemetria veicular" / ausente |
| Nome do provedor de hospedagem | "provedor de infraestrutura" |
| Hostnames internos | `br-01`, `us-02`, `fr-01` (genéricos) |
| Endereços IP públicos | faixas de documentação RFC 5737 (`192.0.2.0/24`, `198.51.100.0/24`, `203.0.113.0/24`) |
| Portas de produção | portas de exemplo, sem relação com o ambiente real |
| Domínios e subdomínios | removidos |
| IDs de nó do Swarm | substituídos por `<node-id>` |
| Relatórios de pacotes e versões | removidos (revelam superfície explorável) |
| Nomes de aplicações internas | descritos por função |
| Credenciais, chaves e tokens | nunca existiram no repositório; ainda assim, o checklist roda contra eles |

## O que foi preservado

- O **raciocínio** de arquitetura e as comparações técnicas.
- As **armadilhas reais** encontradas ao escrever os playbooks.
- A **linha do tempo** e as lições do incidente, sem identificação.
- Os padrões de código (Ansible, Compose, YAML de firewall), reescritos para uso
  genérico.

## Como verificar

O script [`scripts/check-sensitive.ps1`](scripts/check-sensitive.ps1) procura IPs,
domínios, nomes internos e padrões de credencial. Ele é executado antes de cada
commit neste repositório.

```powershell
pwsh ./scripts/check-sensitive.ps1 -NomesInternos 'cliente','provedor','host-01'
```

Os nomes internos são passados por parâmetro de propósito: a lista não fica
escrita no repositório.

## Aviso

Os exemplos não são uma cópia funcional do ambiente. Não tente reutilizá-los como
estão em produção sem revisar variáveis, versões e regras de firewall.
