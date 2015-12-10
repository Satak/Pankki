cls

# $secpw = ConvertTo-SecureString '<yourdbpassword>' -AsPlainText -force
# $en = ConvertFrom-SecureString -securestring $secpw
# $en | Out-File C:\data\dbConnectionString.txt -Encoding utf8

#region Globals 
$version = '1.2'
$exit = $false
$configPath = 'C:\Powershell\Pankki\DBConnection.json'

$DBCon = Get-Content $configPath | ConvertFrom-Json
$DBCon.Password = ConvertTo-PlainText -string $DBCon.Password

$prop = @{
    ServerInstance = $DBCon.ServerInstance
    Database = $DBCon.Database
    Username = $DBCon.Username
    Password = $DBCon.Password
    Query = ''
}

$secKey = Get-SecKey

#endregion

#region functions
function ConvertTo-PlainText
{
param($string)

        $s = ConvertTo-SecureString $string
        $s = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
        $s = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($s)

    return $s
}

function New-Salt
{
    $key = New-Object byte[](32)
    $rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::Create()
    $rng.GetBytes($key)
    return [System.Convert]::ToBase64String($key)
}

function Hash-String
{
param($string,$Cost = 10,$Salt)

    $iteration = [math]::Pow(2,$cost)

    if(!$salt)
    {
        $salt = New-Salt
    }

    $string = $string + $salt

    1..$iteration | %{ 
        $hasher = [System.Security.Cryptography.SHA256]::Create()
        $enc = [system.Text.Encoding]::UTF8
        $bytes = $enc.GetBytes($string) 
        $string = [System.Convert]::ToBase64String($hasher.ComputeHash($bytes))
    }

    return [pscustomobject]@{
        Salt = $salt
        Hash = $string
    }
}

function Test-PW
{
param($Username, $Password)

    $record = Get-UserFromDB -filter "Nimi = '$Username'"

    if($record)
    {
        if((Hash-String -string $Password -salt $record.Salt).Hash -eq $record.Hash)
        {
            return $true
        }
    }

    return $false
}

function Print-BankLogo
{

    Write-Host "                     "  -BackgroundColor DarkYellow
    Write-Host " P A N K K I (v $version) " -ForegroundColor Black -BackgroundColor DarkYellow
    Write-Host "                     "  -BackgroundColor DarkYellow

}

function Get-SecKey
{
    $key = $null
    $prop.Query = "select SecKey FROM SecKey"

    $key = (Invoke-Sqlcmd @prop).SecKey


    if(!$key)
    {
    
        $bitKey = New-Object Byte[] 16 
        [Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($bitKey)
        $byteToString = [System.Convert]::ToBase64String($bitKey)

        $prop.Query = "INSERT into SecKey (SecKey) VALUES ('$byteToString')"
        Invoke-Sqlcmd @prop

        $prop.Query = "select SecKey FROM SecKey"
        $key = (Invoke-Sqlcmd @prop).SecKey

        return [System.Convert]::FromBase64String($key)

    }
    else
    {
        return [System.Convert]::FromBase64String($key)
    }

}

function Add-UserToDB
{
param(
    [string] $Nimi,
    [string] $Sukunimi,
    [int] $Ika,
    [string] $Hash,
    [string] $Salt
)

    try
    {
        $Nimi = $Nimi.substring(0,1).toupper() + $Nimi.substring(1).tolower()
        $Sukunimi = $Sukunimi.substring(0,1).toupper() + $Sukunimi.substring(1).tolower()

        $prop.Query = "INSERT INTO Users (Nimi,Sukunimi,Ika,Enabled,Admin,Hash,Salt) VALUES ('$Nimi','$Sukunimi',$Ika,1,0,'$Hash','$Salt')"
        Invoke-Sqlcmd @prop

        return [pscustomobject]@{
            Status = $true
            Message = "User '$($Nimi) $($Sukunimi)' created successfully"
        }
    }
    catch
    {
        return [pscustomobject]@{
            Status = $false
            Message = $($_.exception.message)
        }
        
    }
}

function Get-UserFromDB
{
param(
    [string] $filter
)

    if($filter)
    {
        $prop.Query = "SELECT * from users where $filter"
    }
    else
    {
        $prop.Query = "SELECT * from users"
    }

    return Invoke-Sqlcmd @prop
}

function Update-Rahat
{
param(
    [int] $ID,
    [int] $Raha
)
    $prop.Query = "UPDATE Users SET Rahat = $Raha WHERE ID = $ID"
    Invoke-Sqlcmd @prop
}

function Delete-UserFromDB
{
param(
    [int] $ID
)

    $prop.Query = "DELETE FROM BankTransaction WHERE SourceID = $ID
    DELETE FROM BankTransaction WHERE TargetID = $ID
    DELETE FROM Users WHERE ID = $ID"

    Invoke-Sqlcmd @prop
}

function Prompt-PINCode
{
        $readPIN = $null

        while($readPIN.Length -ne 4 -OR !($cc1 -match "^[0-9]+$"))
        {
            $readPIN = Read-Host "Anna PIN-koodi (neljä numeroa)" -AsSecureString

            if($readPIN.Length -eq4)
            {
                $PINString = $readPIN | ConvertFrom-SecureString -key $secKey

                $cc1 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($readPIN)
                $cc1 = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($cc1)
            }
        }

        return Hash-String -string $cc1
}

function Add-NewUser
{
  
    #region Prompt menu
    $title = "Uusi käyttäjä"
    $message = "Tehdäänkö käyttäjä?"
    $opList = 'Kyllä','Ei'
    $op = $opList | %{
        New-Object System.Management.Automation.Host.ChoiceDescription "&$_", "$_"
    }
    $rr = $host.ui.PromptForChoice($title, $message, $op, 0) 
    #endregion

    switch ($rr)
        {
            0 {
                $nimi = Read-Host "Etunimi"
                $sukunimi = Read-Host "Sukunimi"

                do
                {
                    $Ika = Read-Host "Ikä"

                }until($Ika -in 18..150)

                $readPIN = $null

                while($readPIN.Length -ne 4 -OR !($cc1 -match "^[0-9]+$"))
                {
                    $readPIN = Read-Host "Anna PIN-koodi (neljä numeroa)" -AsSecureString

                    if($readPIN.Length -eq4)
                    {
                        $PINString = $readPIN | ConvertFrom-SecureString -key $secKey

                        $cc1 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($readPIN)
                        $cc1 = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($cc1)
                    }
                }

                $cryp = Hash-String -string $cc1

                $adder = Add-UserToDB -Nimi $nimi -Sukunimi $sukunimi -Ika $Ika -Hash $cryp.Hash -Salt $cryp.Salt
                return $adder.message     
            }

            1
            {
                return "Käyttäjän teko peruutettiin."
            }
        }
}

function New-Payment
{
param(
$SourceID,
$TargetID,
$Amount
)
    try
    {
        $sourceUser = Get-UserFromDB -filter "ID = $SourceID"

        if($sourceUser.rahat -is [DBNull])
        {
            $sourceUser.rahat = $Amount
        }
        else
        {
            $sourceUser.rahat -= $Amount
        }
        

        Update-Rahat -ID $SourceID -Raha $sourceUser.rahat

        $targetUser = Get-UserFromDB -filter "ID = $TargetID"

        if($targetUser.rahat -is [DBNull])
        {
            $targetUser.rahat = $Amount
        }
        else
        {
            $targetUser.rahat -= $Amount
        }

        Update-Rahat -ID $TargetID -Raha $targetUser.rahat

        return [pscustomobject]@{
            Status = $true
            Saldo = $sourceUser.rahat
            Message = 'Siirto onnistui'
        }

    }
    catch
    {
        return [pscustomobject]@{
            Status = $false
            Saldo = $sourceUser.rahat
            Message = $_.exception.message
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

    if($TargetID)
    {
        $prop.Query = "INSERT INTO BankTransaction (SourceID,TargetID,Amount) VALUES ($SourceID,$TargetID,$Amount)"
    }
    else
    {
        $prop.Query = "INSERT INTO BankTransaction (SourceID,Amount) VALUES ($SourceID,$Amount)"
    }

    Invoke-Sqlcmd @prop
}

function Get-BankTransaction
{
param($ID)

    $prop.Query = "SELECT Amount,
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

    Invoke-Sqlcmd @prop
}

function Invoke-BankFunction
{
param($User)
    $exit = $false
    while(!$exit)
    {
        $title = "Pankki"
        $msg = "Valitse toiminto"
        $toiminnot = '1.Saldo','2.Pano','3.Otto','4.Tilisiirto','5.Vaihda PIN','6.Kirjaudu ulos'

        if($User.Admin)
        {
            $toiminnot += '7.Poista käyttäjä'
        }

        $opt = $toiminnot | % {
            New-Object System.Management.Automation.Host.ChoiceDescription "&$_", $_
        }

        $result = $host.ui.PromptForChoice($title, $msg, $opt, 0) 

        switch ($result)
        {
            0 # Saldo
            {
                cls
                Print-BankLogo
                $user = Get-UserFromDB -filter "ID = $($User.ID)"
                Write-Output "Käyttäjä: $($user.Nimi) $($user.Sukunimi)"
                Write-Output "Saldo: $($user.rahat) EUR"
                [environment]::NewLine
                Write-Output "Tilitapahtumat:"
                
                $tilitapahtumat = Get-BankTransaction -ID $User.ID | %{

                $summa = $_.Amount -as [int]

                    
                    if($_.Kohde -and $_.Kohde -isnot [DBNull])
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

                $user = Get-UserFromDB -filter "ID = $($User.ID)"

                if($user.Rahat -is [DBNull])
                {
                    $user.Rahat = $qm
                }
                else
                {
                    $user.Rahat += $qm
                }

                Update-Rahat -ID $user.id -Raha $user.Rahat
                Add-BankTransaction -SourceID $user.id -Amount $qm

                $userxm = (Get-UserFromDB -filter "ID = $($User.ID)").Rahat

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

                $user = Get-UserFromDB -filter "ID = $($User.ID)"

                $User.Rahat -= $qm
                Update-Rahat -ID $User.ID -Raha $User.Rahat
                Add-BankTransaction -SourceID $user.id -Amount -$qm

                $userxm = (Get-UserFromDB -filter "ID = $($User.ID)").Rahat

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

                $Users = Get-UserFromDB -filter "ID != $($User.ID) AND Admin != 1" | select Nimi,Sukunimi,ID
                $opt = $Users | Out-GridView -PassThru
                $payment = $null
                $payment = New-Payment -SourceID $User.ID -TargetID $opt.ID -Amount $qm
                if($payment.Status)
                {
                    Add-BankTransaction -SourceID $user.id -TargetID $opt.ID -Amount -$qm
                    $payment.Message
                    Write-Output "Siirrettiin $qm EUR tilille '$($opt.Nimi) $($opt.Sukunimi)'. Saldo: $($payment.saldo) EUR"
                }
                else
                {
                    Write-Warning "Tilisiirto epäonnistui"
                    $payment.Message 
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
                $Users = Get-UserFromDB -filter "ID != $($User.ID)" | select Nimi,Sukunimi,ID
                $valinta = $Users | Out-GridView -PassThru

                if($valinta)
                {
                    $title = "Käyttäjän poisto"
                    $msg = "Poistetaanko käyttäjä '$($valinta.Nimi) $($valinta.Sukunimi)' varmasti?"

                    $tt = 'Kyllä','Ei'
                    $opt = $tt | % {
                        New-Object System.Management.Automation.Host.ChoiceDescription "&$_", $_
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

        $newPIN = Prompt-PINCode

        if($newPIN)
        {
            $prop.Query = "UPDATE Users SET Hash = '$($newPIN.Hash)',Salt = '$($newPIN.Salt)' WHERE ID = $ID"
            Invoke-Sqlcmd @prop


            return [pscustomobject]@{
                Status = $true
                Message = 'PIN vaihdettiin onnistuneesti'
            }
        }
        else
        {
            throw 'PIN code prompt failed'
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

function Invoke-FirstPrompt
{
    $title = "Pankki"
    $msg = "Valitse toiminto"
    $optList = '1.Kirjaudu sisään','2.Rekisteröidy','3.Exit'
    $opt = $optList | % {
        New-Object System.Management.Automation.Host.ChoiceDescription "&$_", $_
    }

    return $host.ui.PromptForChoice($title, $msg, $opt, 0) 
}

#endregion

while(!$exit)
{
    cls
    sleep -Milliseconds 100
    print-BankLogo
    sleep -Milliseconds 100

    $result = Invoke-FirstPrompt

    switch($result)
    {  
        0 # Login
        {
            $PIN = $null
            $r = Read-Host "Anna nimi"
            $PIN = Read-Host "Anna PIN-koodi" -AsSecureString

            $PIN = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($PIN)
            $PIN = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($PIN)

            $test = Test-PW -Username $r -Password $PIN

            if($test)
            {
                Write-Output "Kirjautuminen onnistui"
                Invoke-BankFunction -User (Get-UserFromDB -filter "Nimi = '$r'")
            }
            else
            {
                Write-Output 'Kirjaus epäonnistui'
                Read-Host
            }
        }

        1 # register
        {
            Add-NewUser
            Read-Host
        }

        2 # Exit
        {
            $exit = $true
        }
    }

    if($exit)
    {
        Write-Output 'Pankkisovellus suljettu'
        break
    }

}