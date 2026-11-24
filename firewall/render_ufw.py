#!/usr/bin/env python3
"""Renderiza comandos `ufw` a partir da matriz de portas em YAML.

O script APENAS imprime os comandos. Ele não executa nada, não chama `ufw` e não
tem acesso à rede. A aplicação é uma decisão humana, com janela e rollback.

Uso:
    python3 render_ufw.py portas.example.yml
    python3 render_ufw.py portas.example.yml --saida regras.sh
    python3 render_ufw.py portas.example.yml --check   # valida o YAML

Dependência: pyyaml (pip install pyyaml)
"""

from __future__ import annotations

import argparse
import ipaddress
import sys
from pathlib import Path

try:
    import yaml
except ImportError:  # pragma: no cover
    sys.exit("pyyaml não instalado. Rode: pip install pyyaml")

ACOES_VALIDAS = {"allow", "deny", "limit"}
PROTOS_VALIDOS = {"tcp", "udp"}


def carregar(caminho: Path) -> dict:
    with caminho.open(encoding="utf-8") as f:
        dados = yaml.safe_load(f)
    if not isinstance(dados, dict) or "regras" not in dados:
        raise ValueError("YAML inválido: esperado um mapa com a chave 'regras'")
    return dados


def validar(regras: list[dict]) -> list[str]:
    erros: list[str] = []
    for i, regra in enumerate(regras, start=1):
        prefixo = f"regra {i}"
        porta = regra.get("porta")
        if not isinstance(porta, int) or not (1 <= porta <= 65535):
            erros.append(f"{prefixo}: 'porta' deve ser inteiro entre 1 e 65535")

        proto = str(regra.get("proto", "")).lower()
        if proto not in PROTOS_VALIDOS:
            erros.append(f"{prefixo}: 'proto' deve ser tcp ou udp")

        acao = str(regra.get("acao", "")).lower()
        if acao not in ACOES_VALIDAS:
            erros.append(f"{prefixo}: 'acao' deve ser allow, deny ou limit")

        origem = str(regra.get("origem", "any"))
        if origem != "any":
            try:
                ipaddress.ip_network(origem, strict=False)
            except ValueError:
                erros.append(f"{prefixo}: 'origem' inválida ({origem})")

        if not regra.get("servico"):
            erros.append(f"{prefixo}: 'servico' é obrigatório")

    return erros


def comentario(texto: str) -> str:
    # ufw aceita comentário entre aspas simples; removemos aspas do conteúdo.
    limpo = str(texto).replace("'", "").strip()
    return f" comment '{limpo}'" if limpo else ""


def render(regras: list[dict]) -> list[str]:
    linhas: list[str] = [
        "#!/usr/bin/env bash",
        "# Gerado por render_ufw.py a partir da matriz de portas.",
        "# Revise antes de aplicar. Aplique durante janela, com rollback definido.",
        "set -euo pipefail",
        "",
    ]

    for regra in regras:
        porta = regra["porta"]
        proto = str(regra["proto"]).lower()
        acao = str(regra["acao"]).lower()
        origem = str(regra.get("origem", "any"))
        servico = regra.get("servico", "")
        nota = regra.get("comentario", servico)

        if origem == "any":
            cmd = f"ufw {acao} {porta}/{proto}"
        else:
            rede = ipaddress.ip_network(origem, strict=False)
            cmd = f"ufw {acao} from {rede} to any port {porta} proto {proto}"

        linhas.append(f"{cmd}{comentario(nota)}")

    linhas += ["", "# Revisão final e aplicação:", "ufw status verbose", ""]
    return linhas


def main() -> int:
    parser = argparse.ArgumentParser(description="Matriz de portas YAML → comandos ufw")
    parser.add_argument("arquivo", type=Path, help="caminho do YAML da matriz")
    parser.add_argument("--saida", type=Path, help="grava o resultado em arquivo")
    parser.add_argument("--check", action="store_true", help="apenas valida")
    args = parser.parse_args()

    try:
        dados = carregar(args.arquivo)
        erros = validar(dados["regras"])
    except (OSError, ValueError, yaml.YAMLError) as exc:
        print(f"erro: {exc}", file=sys.stderr)
        return 1

    if erros:
        print("Matriz inválida:", file=sys.stderr)
        for erro in erros:
            print(f"  - {erro}", file=sys.stderr)
        return 1

    if args.check:
        print(f"OK: {len(dados['regras'])} regra(s) válida(s).")
        return 0

    linhas = render(dados["regras"])
    texto = "\n".join(linhas)

    if args.saida:
        args.saida.write_text(texto, encoding="utf-8")
        print(f"Comandos gravados em {args.saida}")
    else:
        print(texto)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
