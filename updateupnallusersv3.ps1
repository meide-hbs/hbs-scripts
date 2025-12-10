# Only the proxyAddresses block is changed — everything else stays the same

# Inside the foreach ($user in $users) loop, replace the entire proxyAddresses section with this:

        # ────── PROXYADDRESSES CLEANUP (FIXED) ──────
        $newProxy   = @()
        $removed    = 0
        $hasPrimary = $false
        $hasAlias   = $false

        foreach ($proxy in $user.ProxyAddresses) {
            if ($proxy -match "(?i)@$CustomDomain") {
                Write-Color "      Removing → $proxy" "DarkGray"
                $removed++
                continue
            }
            if ($proxy -eq "SMTP:$newUPN") { $hasPrimary = $true }
            if ($proxy -eq "smtp:$newUPN") { $hasAlias   = $true }
            $newProxy += $proxy
        }

        # Ensure we have a primary (uppercase SMTP)
        if (-not $hasPrimary) {
            $newProxy = @("SMTP:$newUPN") + $newProxy
            Write-Color "   → Added primary: SMTP:$newUPN" "Gray"
        }

        # THIS IS THE CRITICAL FIX → always add at least one lowercase smtp: alias
        if (-not $hasAlias) {
            $newProxy += "smtp:$newUPN"
            Write-Color "   → Added required alias: smtp:$newUPN (prevents 400 error)" "Green"
        }

        if ($removed -gt 0 -or -not $hasPrimary -or -not $hasAlias) {
            $body.proxyAddresses = $newProxy
            $needsUpdate = $true
            Write-Color "   → Removed $removed old proxy address(es)" "Magenta"
        }
