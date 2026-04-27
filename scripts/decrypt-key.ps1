param(
    [Parameter(Mandatory=$true)][string]$EncFile,
    [Parameter(Mandatory=$true)][string]$Passphrase
)

try {
    $encoded = (Get-Content $EncFile -Raw).Trim()
    $raw = [Convert]::FromBase64String($encoded)

    # OpenSSL format: "Salted__" (8) + salt (8) + ciphertext
    if ([System.Text.Encoding]::ASCII.GetString($raw, 0, 8) -ne "Salted__") {
        Write-Error "Invalid encrypted file format"
        exit 1
    }
    $salt = $raw[8..15]
    $ciphertext = $raw[16..($raw.Length - 1)]

    # PBKDF2-SHA256, 10000 iterations, 48 bytes (32 key + 16 IV)
    $pbkdf2 = New-Object System.Security.Cryptography.Rfc2898DeriveBytes(
        [System.Text.Encoding]::UTF8.GetBytes($Passphrase),
        $salt,
        10000,
        [System.Security.Cryptography.HashAlgorithmName]::SHA256
    )
    $derived = $pbkdf2.GetBytes(48)
    $key = $derived[0..31]
    $iv = $derived[32..47]

    # AES-256-CBC decrypt
    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
    $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
    $aes.Key = $key
    $aes.IV = $iv
    $decryptor = $aes.CreateDecryptor()
    $plainBytes = $decryptor.TransformFinalBlock($ciphertext, 0, $ciphertext.Length)
    [System.Text.Encoding]::UTF8.GetString($plainBytes)
} catch {
    exit 1
}
