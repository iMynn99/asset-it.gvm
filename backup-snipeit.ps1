# ==========================================
# SNIPE-IT AUTOMATIC BACKUP
# Backup: 08:00 dan 16:00
# Retention: 7 hari
# ==========================================

$ErrorActionPreference = "Stop"

# ---------- CONFIG ----------
$ProjectDir = "C:\Users\it03.j4\Desktop\Asset-Management\snipe-it"
$BackupRoot = "D:\SnipeIT-Backup"

$DbContainer = "snipe-it-db-1"
$StorageVolume = "snipe-it_storage"

$RetentionDays = 7

# ---------- TIMESTAMP ----------
$Timestamp = Get-Date -Format "yyyy-MM-dd_HHmm"
$BackupDir = Join-Path $BackupRoot $Timestamp
$ConfigDir = Join-Path $BackupDir "config"

$DbFile = Join-Path $BackupDir "database_$Timestamp.sql"
$StorageFile = Join-Path $BackupDir "storage_$Timestamp.tar.gz"
$EnvFile = Join-Path $ConfigDir ".env"

# ---------- CREATE FOLDER ----------
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null

Write-Host ""
Write-Host "============================================"
Write-Host "        SNIPE-IT BACKUP"
Write-Host "        $Timestamp"
Write-Host "============================================"
Write-Host ""

try {

    # ==========================================
    # 1. CHECK DATABASE CONTAINER
    # ==========================================

    Write-Host "[1/4] Checking database..."

    $DbRunning = docker inspect -f '{{.State.Running}}' $DbContainer 2>$null

    if ($DbRunning -ne "true") {
        throw "Database container $DbContainer tidak sedang running."
    }

    Write-Host "      Database container OK." -ForegroundColor Green


    # ==========================================
    # 2. BACKUP DATABASE
    # ==========================================

    Write-Host "[2/4] Backing up database..."

    docker exec $DbContainer sh -c 'mariadb-dump -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE"' > $DbFile

    if (!(Test-Path $DbFile)) {
        throw "File database backup tidak berhasil dibuat."
    }

    if ((Get-Item $DbFile).Length -eq 0) {
        throw "File database backup kosong."
    }

    Write-Host "      Database backup OK." -ForegroundColor Green
    Write-Host "      $DbFile"


    # ==========================================
    # 3. BACKUP STORAGE
    # ==========================================

    Write-Host "[3/4] Backing up Snipe-IT storage..."

    docker run --rm `
        -v "${StorageVolume}:/source:ro" `
        -v "${BackupDir}:/backup" `
        alpine sh -c "cd /source && tar -czf /backup/storage_$Timestamp.tar.gz ."

    if (!(Test-Path $StorageFile)) {
        throw "File storage backup tidak berhasil dibuat."
    }

    if ((Get-Item $StorageFile).Length -eq 0) {
        throw "File storage backup kosong."
    }

    Write-Host "      Storage backup OK." -ForegroundColor Green
    Write-Host "      $StorageFile"


    # ==========================================
    # 4. BACKUP .ENV
    # ==========================================

    Write-Host "[4/4] Backing up .env..."

    $SourceEnv = Join-Path $ProjectDir ".env"

    if (!(Test-Path $SourceEnv)) {
        throw "File .env tidak ditemukan: $SourceEnv"
    }

    Copy-Item `
        -LiteralPath $SourceEnv `
        -Destination $EnvFile `
        -Force

    if (!(Test-Path $EnvFile)) {
        throw "Backup .env gagal."
    }

    Write-Host "      .env backup OK." -ForegroundColor Green
    Write-Host "      $EnvFile"


    # ==========================================
    # RETENTION 7 HARI
    # ==========================================

    Write-Host ""
    Write-Host "Cleaning backups older than $RetentionDays days..."

    $Today = (Get-Date).Date
    $CutoffDate = $Today.AddDays(-$RetentionDays)

    $BackupFolders = Get-ChildItem `
        -LiteralPath $BackupRoot `
        -Directory `
        -ErrorAction SilentlyContinue

    foreach ($Folder in $BackupFolders) {

        # Folder backup harus format:
        # 2026-09-14_0800
        # 2026-09-14_1600

        if ($Folder.Name -match '^(\d{4}-\d{2}-\d{2})_\d{4}$') {

            $FolderDate = [datetime]::ParseExact(
                $Matches[1],
                "yyyy-MM-dd",
                $null
            )

            # Kalau sudah 7 hari atau lebih tua,
            # SEMUA backup pada tanggal tersebut dihapus.
            if ($FolderDate.Date -le $CutoffDate) {

                Write-Host "      Removing old backup: $($Folder.Name)"

                Remove-Item `
                    -LiteralPath $Folder.FullName `
                    -Recurse `
                    -Force
            }
        }
    }


    # ==========================================
    # SUCCESS
    # ==========================================

    Write-Host ""
    Write-Host "============================================" -ForegroundColor Green
    Write-Host "          BACKUP SUCCESS" -ForegroundColor Green
    Write-Host "============================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Backup location:"
    Write-Host "$BackupDir"
    Write-Host ""

    exit 0
}

catch {

    Write-Host ""
    Write-Host "============================================" -ForegroundColor Red
    Write-Host "          BACKUP FAILED" -ForegroundColor Red
    Write-Host "============================================" -ForegroundColor Red
    Write-Host ""
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""

    # Hapus folder backup yang tidak lengkap
    if (Test-Path $BackupDir) {
        Remove-Item `
            -LiteralPath $BackupDir `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue
    }

    exit 1
}