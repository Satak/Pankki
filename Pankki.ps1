cls
#Get-PSSession | Remove-PSSession
if($ps.State -ne "Opened")
{

    #$secpw = ConvertTo-SecureString 'useruser123!' -AsPlainText -force
    #$en = ConvertFrom-SecureString -securestring $secpw
    #$en | Out-File C:\data\pw -Encoding utf8
    #$cred = New-Object PsCredential('sampo\SQLUser',$secpw) 

    $en = Get-Content C:\data\pw
    $secpw = convertto-securestring -string $en
    $cred = [PSCredential]::new('sampo\SQLUser',$secpw)
    $ps = New-PSSession -ComputerName server002.sampo.local -Credential $cred

    $secKey = Get-SecKey -ps $ps
}

function Print-BankLogo
{

    Write-Host "                     "  -BackgroundColor DarkYellow
    Write-Host " P A N K K I (v 1.1) " -ForegroundColor Black -BackgroundColor DarkYellow
    Write-Host "                     "  -BackgroundColor DarkYellow

}

function Get-SecKey
{
param($ps)

    $key = $null

    $key = (Invoke-Command -Session $PS -ScriptBlock {

    $i = "server002\SAMPODB"
    $db = "SampoDB"
    $q = "select SecKey FROM SecKey"

    return Invoke-Sqlcmd -Query $q -ServerInstance $i -Database $db

    }).SecKey

    if(!$key)
    {
    
        $Key = (Invoke-Command -Session $PS -ScriptBlock {

        $Key = New-Object Byte[] 16 
        [Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($Key)
        $byteToString = [System.Convert]::ToBase64String($Key)

        $i = "server002\SAMPODB"
        $db = "SampoDB"
        $q = "INSERT into SecKey (SecKey) VALUES ('$byteToString')"

        Invoke-Sqlcmd -Query $q -ServerInstance $i -Database $db

        $q = "select SecKey FROM SecKey"
        return Invoke-Sqlcmd -Query $q -ServerInstance $i -Database $db

        }).SecKey

        $stringToByte = [System.Convert]::FromBase64String($key)
        return $stringToByte

    }
    else
    {
        $stringToByte = [System.Convert]::FromBase64String($key)
        return $stringToByte
    }

}

function Add-UserToDB
{
param(
    $PS,
    [string] $Nimi,
    [string] $Sukunimi,
    [int] $Ika,
    [bool] $Enabled,
    [string]$PIN
)

    if($Enabled)
    {
        $Enabled = 1
    }
    else
    {
        $Enabled = 0
    }

    Invoke-Command -Session $PS -ScriptBlock {
    param(
        [string] $Nimi,
        [string] $Sukunimi,
        [int] $Ika,
        [int] $Enabled,
        [string] $PIN
    )

    $Nimi = $Nimi.substring(0,1).toupper()+$Nimi.substring(1).tolower()
    $Sukunimi = $Sukunimi.substring(0,1).toupper()+$Sukunimi.substring(1).tolower()

    $q = "INSERT INTO Users (Nimi,Sukunimi,Ika,Enabled,PIN) VALUES ('$Nimi','$Sukunimi',$Ika,$Enabled,'$PIN')"
    $i = "server002\SAMPODB"
    $db = "SampoDB"

    Invoke-Sqlcmd -Query $q -ServerInstance $i -Database $db

    } -ArgumentList $Nimi,$Sukunimi,$Ika,$Enabled,$PIN | select -Property * -ExcludeProperty PSComputerName,RunspaceId
}

function Get-UserFromDB
{
param(
    $PS,
    [string] $filter
)


    Invoke-Command -Session $PS -ScriptBlock {
    param($filter)

    if($filter)
    {
        $q = "SELECT * from users where $filter"
    }
    else
    {
        $q = "SELECT * from users"
    }

    $i = "server002\SAMPODB"
    $db = "SampoDB"

    Invoke-Sqlcmd -Query $q -ServerInstance $i -Database $db

    } -ArgumentList $filter | select -Property * -ExcludeProperty PSComputerName,RunspaceId
}

function Update-Rahat
{
param(
    $PS,
    [int] $ID,
    [int] $Raha
)


    Invoke-Command -Session $PS -ScriptBlock {
    param([int]$ID,[int]$Raha)

    $q = "UPDATE Users
          SET Rahat = $Raha
          WHERE ID = $ID"

    $i = "server002\SAMPODB"
    $db = "SampoDB"

    Invoke-Sqlcmd -Query $q -ServerInstance $i -Database $db

    } -ArgumentList $ID,$Raha | select -Property * -ExcludeProperty PSComputerName,RunspaceId
}

function Delete-UserFromDB
{
param(
    [int] $ID
)


    Invoke-Command -Session $PS -ScriptBlock {
    param([int]$ID)

        $i = "server002\SAMPODB"
        $db = "SampoDB"

        $q = "DELETE FROM BankTransaction WHERE SourceID = $ID
              DELETE FROM BankTransaction WHERE TargetID = $ID
              DELETE FROM Users WHERE ID = $ID"
        Invoke-Sqlcmd -Query $q -ServerInstance $i -Database $db

    } -ArgumentList $ID | select -Property * -ExcludeProperty PSComputerName,RunspaceId
}

function Add-NewUser
{
param($qnimi)

    
    $title = "Uusi käyttäjä"
    $message = "Tehdäänkö käyttäjä '$qnimi'?"

    $k = New-Object System.Management.Automation.Host.ChoiceDescription "&Kyllä", "Tehdään uusi käyttäjä."
    $n = New-Object System.Management.Automation.Host.ChoiceDescription "&Ei", "Ei tehdä uutta käyttäjää."

    $options = [System.Management.Automation.Host.ChoiceDescription[]]($k, $n)

    $result = $host.ui.PromptForChoice($title, $message, $options, 0) 

    switch ($result)
        {
            0 {
                $qsnimi = Read-Host "Anna Sukunimi"

                do
                {
                    $qika = Read-Host "Anna Ikä"

                }until($qika -in 18..150)

                $readPIN = $null
                $cc1 = $null

                while($readPIN.Length -ne 4 -OR !($cc1 -match "^[0-9]+$"))
                {
                    $readPIN = $null
                    $readPIN = Read-Host "Anna PIN-koodi (neljä numeroa)" -AsSecureString

                    if($readPIN.Length -eq4)
                    {

                        $PINString = $readPIN | ConvertFrom-SecureString -key $secKey

                        $cc1 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($readPIN)
                        $cc1 = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($cc1)
                    }
                }
                $cc1 = $null

                Add-UserToDB -PS $ps -Nimi $qnimi -Sukunimi $qsnimi -Ika $qika -Enabled $true -PIN $PINString
                Write-Output "Tehtiin käyttäjä '$qnimi' '$qsnimi', ikä: '$qika'"
            }

            1 {"Käyttäjän teko peruutettiin."}
        }
}

function New-Payment
{
param(
$PS,
$SourceID,
$TargetID,
$Amount
)
    try
    {
        $sourceUser = Get-UserFromDB -PS $ps -filter "ID = $SourceID"
        $sourceUser.rahat -= $Amount
        Update-Rahat -PS $PS -ID $SourceID -Raha $sourceUser.rahat

        $targetUser = Get-UserFromDB -PS $ps -filter "ID = $TargetID"
        $targetUser.rahat += $Amount
        Update-Rahat -PS $PS -ID $TargetID -Raha $targetUser.rahat

        return [pscustomobject]@{
            Status = $true
            Saldo = $sourceUser.rahat
        }

    }
    catch
    {
        return [pscustomobject]@{
            Status = $false
            Saldo = $sourceUser.rahat
        }
    }
}

function Add-BankTransaction
{
param(
[int] $SourceID,
[int] $TargetID,
[int] $Amount
)


    Invoke-Command -Session $PS -ScriptBlock {
    param(
        [int] $SourceID,
        [int] $TargetID,
        [int] $Amount
    )

    $i = "server002\SAMPODB"
    $db = "SampoDB"

    if($TargetID)
    {
        $q = "INSERT INTO BankTransaction (SourceID,TargetID,Amount) VALUES ($SourceID,$TargetID,$Amount)"
    }
    else
    {
        $q = "INSERT INTO BankTransaction (SourceID,Amount) VALUES ($SourceID,$Amount)"
    }

    Invoke-Sqlcmd -Query $q -ServerInstance $i -Database $db

    } -ArgumentList $SourceID,$TargetID,$Amount


}

function Get-BankTransaction
{
param($ID)

    Invoke-Command -Session $PS -ScriptBlock {
    param(
        [int] $ID
    )

    $i = "server002\SAMPODB"
    $db = "SampoDB"
    <#
    $q = "SELECT Amount,(Nimi + ' ' + Sukunimi) as Kohde,TransactionDate FROM BankTransaction 
          left join users on users.id = BankTransaction.targetID
          WHERE SourceID = $ID
          order by TransactionDate desc"
          #>
    $q = "SELECT Amount,
        (Nimi + ' ' + Sukunimi) as Kohde, (select (Nimi + ' ' + Sukunimi) from users where id = $ID) as Siirtaja,
        TransactionDate 

        FROM BankTransaction
        left join users on users.id = BankTransaction.targetID
        WHERE SourceID = $ID

        union

        SELECT Amount,
        (select (Nimi + ' ' + Sukunimi) from users where id = $ID) as Kohde,
        (Nimi + ' ' + Sukunimi) as Siirtaja,
        TransactionDate 

        FROM BankTransaction
        left join users on users.id = BankTransaction.sourceID
        WHERE targetID = $ID

        order by transactiondate desc"

    Invoke-Sqlcmd -Query $q -ServerInstance $i -Database $db

    } -ArgumentList $ID | select -Property * -ExcludeProperty PSComputerName,RunspaceId

}

function Invoke-BankFunction
{
param($User,$ps)
    $exit = $false
    while(!$exit)
    {
        $title = "Pankki"
        $msg = "Valitse toiminto"
        $toiminnot = 'Saldo','Pano','Otto','Tilisiirto','Vaihda PIN','Kirjaudu ulos'

        if($User.Admin)
        {
            $toiminnot += 'Poista käyttäjä'
        }

        $opt = $toiminnot | % {
            [System.Management.Automation.Host.ChoiceDescription]::new($_, $_)
        }

        $result = $host.ui.PromptForChoice($title, $msg, $opt, 0) 

        switch ($result)
        {
            0 # Saldo
            {
                cls
                Print-BankLogo
                $user = Get-UserFromDB -PS $ps -filter "ID = $($User.ID)"
                Write-Output "Käyttäjä: $($user.Nimi) $($user.Sukunimi)"
                Write-Output "Saldo: $($user.rahat) EUR"
                [environment]::NewLine
                Write-Output "Tilitapahtumat:"
                
                $tilitapahtumat = Get-BankTransaction -ID $User.ID | %{

                $summa = $_.Amount -as [int]

                    
                    if($_.Kohde)
                    {
                        $Tapahtuma = 'Tilisiirto'
                        $kohde = $_.Kohde
                        if($kohde -eq "$($User.Nimi) $($User.Sukunimi)")
                        {
                            $summa = [math]::Abs($summa)
                        }
                    }
                    elseif($_.Amount -lt 0)
                    {
                        $Tapahtuma = 'OTTO'
                        $kohde = $null
                    }
                    else
                    {
                        $Tapahtuma = 'PANO'
                        $kohde = $null
                    }

                    

                    [pscustomobject]@{
                        Summa = $summa
                        Tapahtuma = $Tapahtuma
                        Siirtäjä = $_.Siirtaja
                        Kohde = $kohde
                        Päivämäärä = $_.TransactionDate
                    }

                }

                $tilitapahtumat | Format-Table | Out-String
                
                
            }

            1 # Pano
            {
                do
                {
                    $qm = $null
                    try
                    {
                        [int]$qm = Read-Host "[Pano] Syötä summa"
                    }
                    catch
                    {
                        cls
                        Write-Output "Virheellinen muoto. Syötä summa lukuna"
                    }
                }
                until($qm -is [int])

                $user = Get-UserFromDB -PS $ps -filter "ID = $($User.ID)"

                $user.Rahat += $qm
                Update-Rahat -PS $ps -ID $user.id -Raha $user.Rahat
                Add-BankTransaction -SourceID $user.id -Amount $qm

                $userxm = (Get-UserFromDB -PS $ps -filter "ID = $($User.ID)").Rahat

                Write-Output "Talletit tilillesi $qm euroa, saldosi on nyt: $userxm EUR"
            }

            2 # Otto
            {
                do
                {
                    $qm = $null
                    try
                    {
                        [int]$qm = Read-Host "[Otto] Syötä summa"
                    }
                    catch
                    {
                        cls
                        Write-Output "Virheellinen muoto. Syötä summa lukuna"
                    }
                }
                until($qm -is [int])

                $user = Get-UserFromDB -PS $ps -filter "ID = $($User.ID)"

                $User.Rahat -= $qm
                Update-Rahat -PS $ps -ID $User.ID -Raha $User.Rahat
                Add-BankTransaction -SourceID $user.id -Amount -$qm

                $userxm = (Get-UserFromDB -PS $ps -filter "ID = $($User.ID)").Rahat

                Write-Output "Nostit tililtäsi $qm euroa, saldosi on nyt: $userxm EUR"
            }
            
            3 # Tilisiirto
            {
                do
                {
                    $qm = $null
                    try
                    {
                        [int]$qm = Read-Host "[Tilisiirto] Syötä summa"
                    }
                    catch
                    {
                        cls
                        Write-Output "Virheellinen muoto. Syötä summa lukuna"
                    }
                }
                until($qm -is [int])

                $Users = Get-UserFromDB -PS $ps -filter "ID != $($User.ID) AND Admin != 1" | select Nimi,Sukunimi,ID
                $opt = $Users | Out-GridView -PassThru
                $payment = $null
                $payment = New-Payment -PS $ps -SourceID $User.ID -TargetID $opt.ID -Amount $qm
                if($payment.Status)
                {
                    Add-BankTransaction -SourceID $user.id -TargetID $opt.ID -Amount -$qm
                    Write-Output "Onnistunut tilisiirto."
                    Write-Output "Siirrettiin $qm EUR tilille '$($opt.Nimi) $($opt.Sukunimi)'. Saldo: $($payment.saldo) EUR"
                }
                else
                {
                    Write-Warning "Tilisiirto epäonnistui"
                }
            }

            4 # PIN
            {
                $pinAction = $null
                $pinAction = New-PIN -ID $User.ID
                $pinAction.message
            }

            5 # Ulos
            {
                Write-Output 'Kirjauduttiin ulos'
                $exit = $true
            }

            6 # Admin_Poista_kayttaja
            {
                Write-Warning 'Poista käyttäjä -toiminto valittu. Valitse poistettava käyttäjä listalta.'
                $Users = Get-UserFromDB -PS $ps -filter "ID != $($User.ID)" | select Nimi,Sukunimi,ID
                $valinta = $Users | Out-GridView -PassThru

                if($valinta)
                {
                    $title = "Käyttäjän poisto"
                    $msg = "Poistetaanko käyttäjä '$($valinta.Nimi) $($valinta.Sukunimi)' varmasti?"

                    $tt = 'Kyllä','Ei'
                    $opt = $tt | % {
                        [System.Management.Automation.Host.ChoiceDescription]::new($_, $_)
                    }

                    $result = $host.ui.PromptForChoice($title, $msg, $opt, 0) 

                    switch($result)
                    {
                       0
                       {
                            Delete-UserFromDB -ID $valinta.ID
                            Write-Output "Käyttäjä '$($valinta.Nimi) $($valinta.Sukunimi)' poistettiin onnistuneesti"
                       }

                       1
                       {
                            Write-Output "Käyttäjän poisto peruutettiin"
                       }
                    }
                }
                else
                {
                    Write-Output "Käyttäjän poisto peruutettiin"
                }
            }
        }
    }
}

function New-PIN
{
param($ID)

    try
    {

        $readPIN = $null
        $cc1 = $null

        while($readPIN.Length -ne 4 -OR !($cc1 -match "^[0-9]+$"))
        {
            $readPIN = $null
            $readPIN = Read-Host "Anna uusi PIN (neljä numeroa)" -AsSecureString

            if($readPIN.Length -eq4)
            {

                $PINString = $readPIN | ConvertFrom-SecureString -key $secKey

                $cc1 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($readPIN)
                $cc1 = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($cc1)
            }
        }

        

        Invoke-Command -Session $PS -ScriptBlock {
        param([int]$ID,$PINString)

        $q = "UPDATE Users
              SET PIN = '$PINString'
              WHERE ID = $ID"

        $i = "server002\SAMPODB"
        $db = "SampoDB"

        Invoke-Sqlcmd -Query $q -ServerInstance $i -Database $db

        } -ArgumentList $ID,$PINString

        return [pscustomobject]@{
            Status = $true
            Message = 'PIN vaihdettiin onnistuneesti'
        }

    }
    catch
    {
        return [pscustomobject]@{
            Status = $false
            Message = $_.exception.message
        }
    }
}

function Invoke-PINAuthentication
{
param($User)

        $readPIN = $null
        while($readPIN.Length -ne 4)
        {
            $readPIN = Read-Host "Syötä PIN-numero (neljä numeroa)" -AsSecureString
        }

        $BSTR1 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($readPIN)
        $p1 = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR1)

        $SecurePassword2 = ConvertTo-SecureString $User.PIN -Key $secKey
        $BSTR2 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword2)
        $p2 = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR2)

        if($p1 -eq $p2)
        {
            return $true
        }
        return $false
}



while($true)
{
    cls
    sleep -Milliseconds 100
    print-BankLogo
    sleep -Milliseconds 100

    $r = $null
    $r = Read-Host "Anna etunimesi"
    if($r -eq '')
    {
        Write-Output 'Pankkisovellus suljettu'
        break
    }

    $getUser = $null
    $getUser = Get-UserFromDB -PS $ps -filter "Nimi = '$r'"

    if($getUser)
    {
        
        $auth = $null
        
        while(!$auth)
        {
            $auth = Invoke-PINAuthentication -User $getUser
        }
        Write-Output "Kirjautuminen onnistui. Käyttäjä '$($getUser.Nimi) $($getUser.Sukunimi)'. Saldo: $($getUser.Rahat) EUR"
        Invoke-BankFunction -User $getUser -ps $ps
    }
    else
    {
        Write-Output "Ei löytynyt käyttäjää '$r'"
        Add-NewUser -qnimi $r
    }

}