<#
.DESCRIPTION
    The sample scripts are not supported under any Microsoft standard support 
    program or service. The sample scripts are provided AS IS without warranty  
    of any kind. Microsoft further disclaims all implied warranties including,  
    without limitation, any implied warranties of merchantability or of fitness for 
    a particular purpose. The entire risk arising out of the use or performance of  
    the sample scripts and documentation remains with you. In no event shall 
    Microsoft, its authors, or anyone else involved in the creation, production, or 
    delivery of the scripts be liable for any damages whatsoever (including, 
    without limitation, damages for loss of business profits, business interruption, 
    loss of business information, or other pecuniary loss) arising out of the use 
    of or inability to use the sample scripts or documentation, even if Microsoft 
    has been advised of the possibility of such damages.

Purpose: 
    -Gets information on each group in your Yammer network
     
Author:
    Dean Cron

Version:
    1.0

Requirements:

    1. Admin-created bearer token for Yammer authentication:
        https://techcommunity.microsoft.com/t5/yammer-developer/generating-an-administrator-token/m-p/97058

        NOTE - The account this token is created under MUST have private content mode enabled:
        https://learn.microsoft.com/en-us/viva/engage/manage-security-and-compliance/monitor-private-content

.EXAMPLE
    .\Get-YammerGroupInfo.ps1
#>

<############    STUFF YOU NEED TO MODIFY    ############>

#Replace BearerTokenString with the Yammer API bearer token you generated. See "Requirements" near the top of the script.
$Global:YammerAuthToken = "BearerTokenString"

$ReportOutput = "C:\Temp\YammerGroupInfo{0}.csv" -f [DateTime]::Now.ToString("yyyy-MM-dd_hh-mm-ss")
<############    YOU SHOULD NOT HAVE TO MODIFY ANYTHING BELOW THIS LINE    ############>

#Create header with access token
$Global:header = @{"Authorization" = "Bearer $YammerAuthToken"}

#Function to get all groups
Function Get-YammerGroups($page, $allGroups) {
    if (!$page) {
        $page = 1
    }

    if (!$allGroups) {
        $allGroups = New-Object System.Collections.ArrayList($null)
    }

    $urlToCall = "https://www.yammer.com/api/v1/groups.json"
    $urlToCall += "?page=" + $page;

    #API only returns 50 results per page, so we need to loop through all pages
    Write-Host "Retrieving page $page of groups list" -Foreground Yellow
    $webRequest = Invoke-WebRequest -Uri $urlToCall -Method Get -Headers $header

    if ($webRequest.StatusCode -eq 200) {
        $results = $webRequest.Content | ConvertFrom-Json

        if ($results.Length -eq 0) {
            return $allGroups
        }
        $allGroups.AddRange($results)
    }

    if ($allGroups.Count % 50 -eq 0) {
        $page = $page + 1
        return Get-YammerGroups $page $allGroups
    }
    else {
        return $allGroups
    }
}

#groups.json will occasionally return duplicates in results. This should remove them.
$results = Get-YammerGroups

#Array to store Result
$ResultSet = @()

$results | ForEach-Object {
    
    $gID = $_.Id -as [decimal]
    Write-Host "Processing Group:" $_.Name -f Yellow
    do {
        $rateLimitHit = $false
        try{
            #Get the group properties.
            $getGroupInfo = (Invoke-WebRequest "https://www.yammer.com/api/v1/groups/$gID.json" -Headers $header -Method GET).content | ConvertFrom-Json

            $Result = new-object PSObject
            $Result | add-member -membertype NoteProperty -name "GroupID" -Value $gID
            $Result | add-member -membertype NoteProperty -name "GroupName" -Value $getGroupInfo.name
            $Result | add-member -membertype NoteProperty -name "MemberCount" -Value $getGroupInfo.stats.members
            $Result | add-member -membertype NoteProperty -name "LastMessageAt" -Value $getGroupInfo.stats.last_message_at

            #If the group has admins, add their info to the results
            if($getGroupInfo.has_admin){
                $admins = $null
                $getGroupAdmins = (Invoke-WebRequest "https://www.yammer.com/api/v1/groups/$gID/members.json" -Headers $header -Method GET).content | ConvertFrom-Json

                $groupAdmins = $getGroupAdmins.users | Where-Object {$_.is_group_admin  -eq "true"}

                $groupAdmins | ForEach-Object {
                    $admins += $_.full_name + " " + $_.email + ";"
                }

                $Result | add-member -membertype NoteProperty -name "GroupAdmins" -Value $admins
                $ResultSet += $Result
            }
            else{
                $Result | add-member -membertype NoteProperty -name "GroupAdmins" -Value "No Admins"
                $ResultSet += $Result
            }
        }
        catch {
            if($_.Exception.Response.StatusCode.Value__ -eq "404"){
                #Typically thrown when the group isn't found. No exit, try next group.
                Write-Host "API reports 404, typically caused if the group "+($_.Name)+" wasn't found or isn't accessible." -ForegroundColor Red
                Write-Host "Be sure the account that generated the developer token has Private Content Mode enabled." -ForegroundColor Red
            }
            elseif($_.Exception.Response.StatusCode.Value__ -eq "429" -or $_.Exception.Response.StatusCode.Value__ -eq "503"){
                #Thrown when rate limiting is hit. No exit, retry.
                #https://learn.microsoft.com/en-us/rest/api/yammer/rest-api-rate-limits#yammer-api-rate-limts
                $rateLimitHit = $true
            }
            else{
                #Fallback, no idea what happened to get us here.
                $e = $_.Exception.Response.StatusCode.Value__
                $l = $_.InvocationInfo.ScriptLineNumber
                Write-Host "Failed to get info for group "$_.Name -ForegroundColor Red
                Write-Host "error $e on line $l" -ForegroundColor Red
            }

            if ($rateLimitHit) {
                #429 or 503: Sleep for a bit before retrying
                Write-Host "Rate limit hit, sleeping for 10 seconds before retrying group "$_.Name -ForegroundColor Yellow
                Start-Sleep -Seconds 10
            }
        }
    } while ($rateLimitHit)
}

#Export Result to csv file
$ResultSet |  Export-Csv $ReportOutput -notypeinformation
 
Write-Host "Report created successfully. See $ReportOutput" -f Green
