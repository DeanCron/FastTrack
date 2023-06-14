# ==================================================================
# Microsoft provides programming examples for illustration only, without warranty either expressed or
# implied, including, but not limited to, the implied warranties of merchantability and/or fitness 
# for a particular purpose.
# 
# This sample assumes that you are familiar with the programming language being demonstrated and the 
# tools used to create and debug procedures. Microsoft support professionals can help explain the 
# functionality of a particular procedure, but they will not modify these examples to provide added 
# functionality or construct procedures to meet your specific needs. if you have limited programming 
# experience, you may want to contact a Microsoft Certified Partner or the Microsoft fee-based consulting 
# line at (800) 936-5200.
#
# For more information about Microsoft Certified Partners, please # visit the following Microsoft Web site:
# https://partner.microsoft.com
# -------------------------------------------------------------------
#
# Purpose: Exports files from a Yammer network for specific date ranges
# https://learn.microsoft.com/en-us/rest/api/yammer/yammer-files-export-api
#
# Requirements: Admin-created bearer token for Yammer app authentication:
# https://learn.microsoft.com/en-us/rest/api/yammer/app-registration
# https://techcommunity.microsoft.com/t5/yammer-developer/generating-an-administrator-token/m-p/97058
#
# ===================================================================
Param(
    [Parameter(Mandatory = $true)]
    [ValidateScript(
    {
        try{
            [datetime]::ParseExact($psitem ,'yyyy-MM-dd' ,[System.Globalization.CultureInfo](Get-Culture))
        }
        catch{
            throw "StartDate is in the wrong format. Use format: YYYY-MM-DD"
            exit
        }    
    })]
    [string]$StartDate,

    [Parameter(Mandatory = $true)]
    [ValidateScript(
    {
        try{
            [datetime]::ParseExact($psitem ,'yyyy-MM-dd' ,[System.Globalization.CultureInfo](Get-Culture))
        }
        catch{
            throw "EndDate is in the wrong format. Use format: YYYY-MM-DD"
            exit
        }
    })]
    [string]$EndDate
)

<############    STUFF YOU NEED TO MODIFY    ############>
#Replace BearerTokenString with the Yammer API bearer token you generated. See "Requirements" near the top of the script.
$Global:YammerAuthToken = "BearerTokenString"

#Change the folder path to an existing target location you want the output and log saved to
$rootPath = "C:\Temp"

<############    YOU SHOULD NOT HAVE TO MODIFY ANYTHING BELOW THIS LINE    ############>
function Get-YammerAuthHeader {
    @{ AUTHORIZATION = "Bearer $YammerAuthToken" }
}

Function Write-Log {
    [CmdletBinding()]
    Param(
    [Parameter(Mandatory=$False)]
    [ValidateSet("INFO","WARN","ERROR")]
    [String]
    $Level = "INFO",

    [Parameter(Mandatory=$True)]
    [string]
    $Message,

    [Parameter(Mandatory=$False)]
    [string]
    $logfile
    )

    $Stamp = (Get-Date).toString("yyyy/MM/dd HH:mm:ss")
    $Line = "$Stamp $Level $Message"
    If($logfile) {
        if(!(Test-Path -Path $logfile )){
            $null = New-Item -Path $logfile -ItemType "file" -Force
        }
        Add-Content $logfile -Value $Line -Force
    }
    Else {
        Write-Output $Line
    }
}

Write-Host "Starting export for date range" $StartDate "to" $EndDate -ForegroundColor Green

#Populating key vars
$activityLogName = "ScriptLog{0}.txt" -f [DateTime]::Now.ToString("yyyy-MM-dd_hh-mm-ss")
$activityLog = $rootPath + "\Export" +(Get-Date -Date $StartDate -format "yyyyMMdd") +"to" +(Get-Date -Date $EndDate -format "yyyyMMdd" ) +"\" +$activityLogName
$authHeader = Get-YammerAuthHeader

#Create a separate folder in $rootPath for the output of each export run
$exportPath = $rootPath +"\Export" +(Get-Date -Date $StartDate -format "yyyyMMdd") +"to" +(Get-Date -Date $EndDate -format "yyyyMMdd" )
if(!(Test-Path -Path $exportPath)){
    New-Item -ItemType directory -Path $exportPath | Out-Null
}
Write-Log -Level "INFO" -Message "Created output directory $exportPath" -logFile $activityLog

#Build the export request URL
$Uri = "https://www.yammer.com/api/v1/export/requests?"
$Uri += "since=" +$(Get-Date -Date $StartDate -Format s) +"&until=" +$(Get-Date -Date $EndDate -Format s)

#Send the export request. If successful, grab the user_request_id value from the response
#Details: https://learn.microsoft.com/en-us/rest/api/yammer/yammer-files-export-api#creating-a-request-to-export-files
try{
    Write-Log -Level "INFO" -Message "Sending export request. Uri: $Uri" -logFile $activityLog
    Write-Host "Sending export request"
    $response = Invoke-RestMethod -uri $Uri -Method POST -Headers $authHeader
    $userRequestID = $response.user_request_id
    Write-Log -Level "INFO" -Message "Export request successful, user request id: $userRequestID" -logFile $activityLog
}
catch{
    $e = $error[0]
    $l = $_.InvocationInfo.ScriptLineNumber

    if($_.Exception.Response.StatusCode.Value__ -eq "401")
    {
        $err401 = "Export api reported ACCESS DENIED. Please ensrure you're using a valid developer token for the YammerAuthToken variable."
        Write-Log -Level "ERROR" -Message "Export request failed on line $l, exiting script." -logFile $activityLog
        Write-Log -Level "ERROR" -Message $err401 -logFile $activityLog
        Write-Host $err401 "`nExiting script. See $activityLog for more information" -ForegroundColor Red
    }
    else{
        Write-Log -Level "ERROR" -Message "Export request failed on line $l, ending script" -logFile $activityLog
        Write-Log -Level "ERROR" -Message "Error Message: $($e.Exception.Message)" -logFile $activityLog
        Write-Log -Level "ERROR" -Message "Inner exception: $($e.ErrorDetails.Message)" -logFile $activityLog
        Write-Host "Failed while sending export request, see $activityLog for more information" -ForegroundColor Red
    }
    exit
}

#Build the URL for the status check
#Details: https://learn.microsoft.com/en-us/rest/api/yammer/yammer-files-export-api#check-status-of-your-data-export
$statusURI = "https://www.yammer.com/api/v1/export/requests/$($userRequestID)"
$statusResponse = ""

#Send the request to check status on the export request.
try{
    Write-Log -Level "INFO" -Message "Sending status request. Uri: $statusURI" -logFile $activityLog
    Write-Host "Checking the status of the export request, this may take some time"
    #See comments in 'catch' for why I added the short sleep here, haven't had the issue pop up since
    start-sleep -seconds 5
    $statusResponse = Invoke-RestMethod -uri $statusURI -Method GET -Headers $authHeader
}
catch{
    #Not entirely sure why this happens, seems to be timing ¯\_(ツ)_/¯, but I've seen "No export request was found for the request_id" thrown a few times
    #If the 5sec sleep above doesn't work, or we end up here for any other reason, admin needs to check the error and restart this specific export
    $e = $error[0]
    $l = $_.InvocationInfo.ScriptLineNumber
    Write-Log -Level "ERROR" -Message "Status request failed on line $l, exiting script. Please retry export for dates $StartDate to $EndDate" -logFile $activityLog
    Write-Log -Level "ERROR" -Message "Error Message: $($e.Exception.Message)" -logFile $activityLog
    Write-Log -Level "ERROR" -Message "Inner exception: $($e.ErrorDetails.Message)" -logFile $activityLog
    Write-Host "Failed while attempting export status check, see $activityLog for more information" -ForegroundColor Red
    exit
}

#Might take a while, setting the wait between status checks to 2min (which could still be chatty in the activity log)
while(!($statusResponse.status.contains("COMPLETE")))
{
    $currentStatus = $statusResponse.status
    Write-Log -Level "INFO" -Message "Current status: $currentStatus; retrying shortly" -logFile $activityLog
    start-sleep -seconds 120
    $statusResponse = Invoke-RestMethod -uri $statusURI -Method GET -Headers $authHeader
}            

#Will it blend? Moment of truth, attempt to download the export
if (($statusResponse.status.contains("COMPLETE"))) {
    if($statusResponse.data){
        $urlArray = $statusResponse.data.split([System.Environment]::NewLine)
        try {
            Write-Host "Status: COMPLETE. Attempting to download export package"

            foreach ($urlEntry in $urlArray){
                [uri]$dlUri = [string]$urlEntry
                $dlOutputFile = $exportPath.ToString() +"\YammerFilesExport{0}.zip" -f [DateTime]::Now.ToString("yyyy-MM-dd_hh-mm-ss")
                Write-Log -Level "INFO" -Message "Starting download of export file $dlUri" -logFile $activityLog
                Invoke-WebRequest -Uri $dlUri -OutFile $dlOutputFile
                Write-Log -Level "INFO" -Message "Download complete, files downloaded to $dlOutputFile" -logFile $activityLog
                start-sleep 5
            }
            Write-Host "Export for date range $StartDate to $EndDate complete, the script logfile and export(s) can be found in $exportPath" -ForegroundColor Green
        }
        catch{
            $e = $error[0]
            $l = $_.InvocationInfo.ScriptLineNumber
            Write-Log -Level "ERROR" -Message "Download of export file failed on line $l, ending script" -logFile $activityLog
            Write-Log -Level "ERROR" -Message "Error Message: $($e.Exception.Message)" -logFile $activityLog
            Write-Log -Level "ERROR" -Message "Inner exception: $($e.ErrorDetails.Message)" -logFile $activityLog
            Write-Host "Failed while attempting download of export file, see $activityLog for more information" -ForegroundColor Red
            exit
        }
    }
    else{
        #AFAIK, the only reason for the 'data' property to come back empty on an HTTP 200 is if there were no files to export in the given timeframe
        $messageString = "No files found to download for timeframe $StartDate to $EndDate"
        Write-Log -Level "INFO" -Message  $messageString -logfile $activityLog
        Write-Host "$messageString. Script exiting, see $activityLog for more information"
    }
}