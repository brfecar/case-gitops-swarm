<#
.SYNOPSIS
    Checklist de sanitização antes de publicar o repositório.

.DESCRIPTION
    Procura IPs reais, domínios, e-mails, credenciais, tokens, chaves privadas e
    IDs de chat. Nomes internos (cliente, provedor, hostnames) são passados por
    parâmetro para não ficarem escritos no próprio repositório.

    Retorna código 1 se encontrar algo fora da lista de exceções (faixas de
    documentação RFC 5737).

.EXAMPLE
    pwsh ./scripts/check-sensitive.ps1

.EXAMPLE
    pwsh ./scripts/check-sensitive.ps1 -NomesInternos 'cliente-x','provedor-y','host-01'
#>

[CmdletBinding()]
param(
    [string[]]$NomesInternos = @()
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot

# Arquivos/pastas que não entram na varredura (comparados com barras normais)
$ignorar = @(
    '/.git/',
    '/node_modules/',
    '/.opencode/',
    '/relatorios/',
    '/evidencias/'
)

$padroes = @(
    @{ Nome = 'IPv4 fora de faixa de documentação'; Regex = '\b(?:\d{1,3}\.){3}\d{1,3}\b' },
    @{ Nome = 'Domínio';                           Regex = '\b[a-zA-Z0-9][a-zA-Z0-9.-]*\.(com|net|org|br|io|dev|cloud|app)\b' },
    @{ Nome = 'Credencial aparente';               Regex = '(?i)(senha|password|passwd|token|secret|api[_-]?key|private[_-]?key)\s*[:=]\s*\S+' },
    @{ Nome = 'Chave SSH privada';                 Regex = 'ssh-(rsa|ed25519|dss)\s+AAAA' },
    @{ Nome = 'Chave privada PEM';                 Regex = '-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED )?PRIVATE KEY-----' },
    @{ Nome = 'Token de serviço';                  Regex = '\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|AIza[A-Za-z0-9_-]{20,}|(?:AKIA|ASIA)[A-Z0-9]{12,}|sk-[A-Za-z0-9_-]{20,})\b' },
    @{ Nome = 'E-mail';                            Regex = '\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b' },
    @{ Nome = 'ID de chat/canal';                  Regex = '(?<!\d)-\d{10,}(?!\d)' }
)

if ($NomesInternos.Count -gt 0) {
    $alternativas = $NomesInternos | ForEach-Object { [regex]::Escape($_) }
    $padroes += @{
        Nome  = 'Nome interno (informado)'
        Regex = "(?i)\b($($alternativas -join '|'))\b"
    }
}

function Test-ExcecaoIPv4 {
    param([string]$Valor)

    $faixasPermitidas = @('192.0.2.', '198.51.100.', '203.0.113.', '127.0.0.1', '0.0.0.0')
    foreach ($faixa in $faixasPermitidas) {
        if ($Valor.StartsWith($faixa)) { return $true }
    }
    return $false
}

$arquivos = Get-ChildItem -Path $repoRoot -Recurse -File -Force |
    Where-Object {
        $caminho = $_.FullName.Replace('\', '/')
        if ($caminho -eq $PSCommandPath.Replace('\', '/')) { return $false }
        -not ($ignorar | Where-Object { $caminho.Contains($_) })
    } |
    Where-Object { $_.Extension -notin @('.png', '.jpg', '.jpeg', '.gif', '.ico', '.pdf', '.zip', '.gz') }

$achados = New-Object System.Collections.Generic.List[object]

foreach ($arquivo in $arquivos) {
    $relativo = $arquivo.FullName.Replace($repoRoot + '\', '')
    $linhaAtual = 0

    Get-Content -Path $arquivo.FullName -ErrorAction SilentlyContinue | ForEach-Object {
        $linhaAtual++
        $linha = $_

        foreach ($padrao in $padroes) {
            $ocorrencias = [regex]::Matches($linha, $padrao.Regex)
            foreach ($m in $ocorrencias) {
                if ($padrao.Nome -like 'IPv4*' -and (Test-ExcecaoIPv4 -Valor $m.Value)) {
                    continue
                }

                $achados.Add([pscustomobject]@{
                    Arquivo = $relativo
                    Linha   = $linhaAtual
                    Regra   = $padrao.Nome
                    Trecho  = $m.Value
                })
            }
        }
    }
}

if ($achados.Count -eq 0) {
    Write-Host "OK: nenhum dado sensível encontrado em $($arquivos.Count) arquivo(s)." -ForegroundColor Green
    exit 0
}

Write-Host "ATENÇÃO: $($achados.Count) ocorrência(s) encontrada(s)." -ForegroundColor Yellow
$achados | Format-Table -AutoSize -Wrap

Write-Host ""
Write-Host "Corrija antes do 'git add'. Depois de publicado, o histórico permanece." -ForegroundColor Yellow
exit 1
