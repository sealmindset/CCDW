param($PipePath)
if (Test-Path $PipePath) { exit 0 } else { exit 1 }
