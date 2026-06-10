# Kenney CC0 paketlerini (tilemap_packed.png) ve Public Pixel fontunu indirir.
# Kenney URL'leri hash icerir ve paket yeniden yuklenince curur; oyle olursa
# guncel linki kenney.nl/assets/<paket> sayfasindan alip asagiyi guncelle.
# Acilmis sheet'ler repoya commit'lendigi icin bu script sadece ilk kurulumda gerekir.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$downloads = Join-Path $root 'assets\downloads'
New-Item -ItemType Directory -Force $downloads | Out-Null

$packs = @(
    @{ name = 'tiny-town';   url = 'https://kenney.nl/media/pages/assets/tiny-town/a415fbeb49-1735736916/kenney_tiny-town.zip' },
    @{ name = 'tiny-battle'; url = 'https://kenney.nl/media/pages/assets/tiny-battle/c1c25ac1f3-1691487575/kenney_tiny-battle.zip' }
)
foreach ($p in $packs) {
    $dest = Join-Path $root ('assets\kenney\' + $p.name)
    if (Test-Path (Join-Path $dest 'tilemap_packed.png')) { Write-Host "$($p.name): zaten var"; continue }
    $zip = Join-Path $downloads ($p.name + '.zip')
    Write-Host "$($p.name) indiriliyor..."
    curl.exe -sL --retry 3 -o $zip $p.url
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $zip)) {
        Write-Error ("Indirme basarisiz: " + $p.url)
        exit 1
    }
    $tmp = Join-Path $downloads ($p.name + '_extract')
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    try {
        Expand-Archive $zip -DestinationPath $tmp -Force
    } catch {
        Write-Error ("Zip acilamadi -- URL curumus olabilir. Guncel linki su sayfadan al: https://kenney.nl/assets/" + $p.name)
        exit 1
    }
    $sheet = Get-ChildItem $tmp -Recurse -Filter 'tilemap_packed.png' | Select-Object -First 1
    if (-not $sheet) { Write-Error "$($p.name): tilemap_packed.png arsivde yok"; exit 1 }
    New-Item -ItemType Directory -Force $dest | Out-Null
    Copy-Item $sheet.FullName (Join-Path $dest 'tilemap_packed.png') -Force
    $lic = Get-ChildItem $tmp -Recurse -Filter 'License.txt' | Select-Object -First 1
    if ($lic) { Copy-Item $lic.FullName (Join-Path $dest 'License.txt') -Force }
    Write-Host "$($p.name): tamam"
}

# Public Pixel (GGBotNet, CC0) -- Turkce glyph'ler tam
$fontDir = Join-Path $root 'assets\fonts'
$font = Join-Path $fontDir 'PublicPixel.ttf'
if (-not (Test-Path $font)) {
    New-Item -ItemType Directory -Force $fontDir | Out-Null
    Write-Host 'PublicPixel.ttf indiriliyor...'
    curl.exe -sL --retry 3 -o $font 'https://raw.githubusercontent.com/ggbotnet/fonts-cc0/main/Public%20Pixel/TrueType%20(.ttf)/PublicPixel.ttf'
    if ($LASTEXITCODE -ne 0) { Write-Error 'Font indirilemedi'; exit 1 }
}
Write-Host 'Asset kurulumu tamam.'
