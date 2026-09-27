param(
    [int]$Vueltas = 15,
    [string]$Base = "http://localhost"
)

$Rutas = @(
    "/",
    "/index.php",
    "/index.php?option=com_users&view=login",
    "/administrator/",
    "/templates/cassiopeia/images/logo.svg",
    "/ruta-inexistente",
    "/healthz",
    "/grafana/api/health",
    "/jupyter/api"
)

Write-Host "Generando trafico contra $Base ($Vueltas vueltas x $($Rutas.Count) rutas)..."
$total = 0

for ($i = 1; $i -le $Vueltas; $i++) {
    foreach ($ruta in $Rutas) {
        try {
            $r = Invoke-WebRequest -Uri "$Base$ruta" -Method GET -TimeoutSec 15 `
                                   -MaximumRedirection 0 -ErrorAction Stop -UseBasicParsing
            $codigo = $r.StatusCode
        } catch {
            if ($null -ne $_.Exception.Response) {
                $codigo = [int]$_.Exception.Response.StatusCode
            } else {
                $codigo = "error"
            }
        }
        Write-Host ("  {0,-3} {1,-45} -> {2}" -f $i, $ruta, $codigo)
        $total++
    }
    Start-Sleep -Seconds 1
}

Write-Host ""
Write-Host "Listo: $total peticiones enviadas."