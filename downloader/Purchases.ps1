#requires -Version 5.1
function Invoke-PurchaseTool([string[]]$Arguments) {
    try { Invoke-Cpp $Arguments 90 }
    catch [TimeoutException] { throw (Get-IpaText 'История покупок: ответ не получен за 90 секунд. Повторите запрос.') }
}
function Get-OwnedApplications {
    $seen = @{}
    $apps = [Collections.Generic.List[object]]::new()
    # Commerce history defaults to 90 days. Query every calendar year, including
    # empty years. ipatool-cpp follows all invoice pages within each range.
    # Do not query the public catalog: delisted apps can still be in invoices.
    for ($year = [DateTime]::Now.Year; $year -ge 2008; $year--) {
        Test-Cancel
        Send-Event 'status' ((Get-IpaText 'История покупок за {0} год…') -f $year)
        $result = Invoke-PurchaseTool @('list-purchases','--range',("$year-all"))
        if ($result.ExitCode -ne 0) {
            # Error output can contain invoice details; expose only the HTTP code.
            $code = [regex]::Match($result.Text,'HTTP (-?\d+)').Groups[1].Value
            if ($code) { throw ((Get-IpaText 'Не удалось получить покупки за {0} год (HTTP {1}). Повторите запрос.') -f $year,$code) }
            throw ((Get-IpaText 'Не удалось получить покупки за {0} год. Повторите вход и запрос.') -f $year)
        }
        $record = @(Read-Records $result.Text | Where-Object { $_.PSObject.Properties['apps'] }) | Select-Object -Last 1
        $items = @(Get-Field $record 'apps' | Where-Object { $_ })
        $count = 0
        if ($null -eq $record -or $record.apps -isnot [Array] -or -not [int]::TryParse([string](Get-Field $record 'count'),[ref]$count) -or $count -ne $items.Count) {
            throw (Get-IpaText 'Apple вернула некорректный список покупок.')
        }
        foreach ($item in $items) {
            Test-Cancel
            # Commerce also contains books, music and in-app purchases.
            if ([string](Get-Field $item 'kind') -ne 'iOS App') { continue }
            $id = Resolve-AppId ([string](Get-Field $item 'id'))
            if ($seen.ContainsKey($id)) { continue }
            $seen[$id] = $true
            $name = [string](Get-Field $item 'name')
            if (-not $name) { $name = $id }
            $apps.Add([pscustomobject]@{Id=$id;Name=$name;Bundle='';PurchaseDate=[string](Get-Field $item 'purchaseDate')})
        }
        Send-Event 'log' ((Get-IpaText 'Проверен {0} год. Найдено приложений: {1}.') -f $year,$apps.Count)
    }
    Test-Cancel
    # Emit only after every year succeeds: never present a partial list as complete.
    return $apps.ToArray()
}