 param
(
    [Parameter(Mandatory=$True)]
    [string] $environment,

    [Parameter(Mandatory=$True)]
    [string] $keyVault
)


$VerbosePreference = "Continue"
$ErrorActionPreference = “Stop”

try
{
    Write-Verbose "BEGIN: Send-DailyResults"

    .\Connect-Azure.ps1

    Write-Verbose "Runbook parameter: environment - $environment"
    $subscription = Get-AutomationVariable -Name "subscription"
    Write-Verbose "Automation variable: subscription - $subscription"
    $resourceGroupName = Get-AutomationVariable -Name "automationResourceGroup"
    Write-Verbose "Automation variable: resourceGroupName - $resourceGroupName"
    $automationAcctName = Get-AutomationVariable -Name "automationAccountName"
    Write-Verbose "Automation variable: automationAcctName - $automationAcctName"
    $acctName = Get-AutomationVariable -Name "smtpAccountName"
    Write-Verbose "Automation variable: smtpAccountName - $acctName"
    $acct = Get-AutomationVariable -Name "smtpAccount"
    Write-Verbose "Automation variable: smtpAccountName - $acct"
    $acctPwd = (Get-AzureKeyVaultSecret -VaultName $keyVault -Name $acct).SecretValueText
    $server = Get-AutomationVariable -Name "smtpServer"
    Write-Verbose "Automation variable: smtpServer - $server"
    $port = Get-AutomationVariable -Name "smtpPort"
    Write-Verbose "Automation variable: smtpPort - $port"
    $recipients = Get-AutomationVariable -Name "mailRecipients"
    Write-Verbose "Automation variable: recipients - $recipients"

    $today = Get-Date
    $endTimeStr = ("{0}/{1}/{2} {3}:00:00" -f $today.Month, $today.Day, $today.Year, $today.Hour)
    $endTime = Get-Date $endTimeStr
    $startTime = $endTime.AddHours(-24)
    Write-Verbose "Gathering results from $startTime - $endTime (UTC)"   
    
    $results = "<b>Today's test results:</br></br><u>Passed:</u></b></br>"    
    $failedJobResults = "<b><u>Failed:</u></b></br>"
    $failures = @{
        QuotaFailures = ""
        CapacityFailures = ""
        KnownFailures = ""
        OtherFailures = "" 
        KnownTestSuspensions = ""
    }      
    $unknownResults = "<b><u>Suspended:</u></b></br>"
    $noUnknownResults = $True  
    $knownIssues = "<b><u>Known Issues | Product Bugs:</u></b></br> "     
    $noKnownEvictions = $True     
    $knownFailuresList = ("Test-SpLnxEnableOsKekMdLvm", "Test-SpLnxEnableOsKekMdLvmUpdateStopstart",`
        "Test-SpWinEnableAllKekMdThenDisableData", "Test-SpWinEnableAllNoKekMdThenDisableData",`
        "Test-SpLnxEnableOsKekMdUpdateStopstart", "Test-SpLnxEnableAllKekMdUpdateStopstart",` 
        "Test-SpLnxEnableAllKekNdUpdateStopstart", `
        "Test-SpLnxEnableDataKekMdThenDisableEnable", "Test-SpLnxEnableDataKekNdThenDisableEnable")   

    $secPwd = ConvertTo-SecureString $acctPwd -AsPlainText -Force
    $creds = New-Object System.Management.Automation.PSCredential ($acctName, $secPwd)       
    $recipientArr = $recipients.Split(";")        
    $azAutoBlade = ("https://ms.portal.azure.com/#resource/subscriptions/{0}/resourcegroups/{1}/providers/Microsoft.Automation/automationAccounts/{2}" -f $subscription, $resourceGroupName, $automationAcctName)
    $azAutoLink = ("<p>Automation Account: <a href=`"{0}`">$automationAcctName</a></p>"-f $azAutoBlade)

    $jobsCompleted = 0
    $jobsPassed = 0
    $jobsFailed = 0
    $quotaFailuresTotal = 0 
    $capacityFailuresTotal = 0
    $knownFailuresTotal = 0
    $otherFailuresTotal = 0
    $knownEvictionsTotal = 0
    $errorLogs = "</br>"
    $jobs = Get-AzureRmAutomationJob -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAcctName -StartTime $startTime -EndTime $endTime
    foreach($job in $jobs)
    {
        $fullJob = Get-AzureRmAutomationJob -Id $job.JobId -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAcctName
        $envTag = $fullJob.JobParameters["environmenttag"]
        if(($fullJob.RunbookName -like "Test-*") -and ($environment -eq $envTag))
        {
            Write-Verbose ("Getting results for {0} ({1})" -f $fullJob.RunbookName, $fullJob.JobId)
            $jobsCompleted++
            if($fullJob.Status -in "Completed")
            {
                Write-Verbose ("Adding Passed result for {0}" -f $fullJob.RunbookName)
                $results += ("{0}: Passed           [Job Id: {1} ]</br>" -f $fullJob.RunbookName, $job.JobId)
                $jobsPassed++
            }
            elseif($fullJob.Status -in "Failed")
            {
                Write-Verbose ("Adding Failed result for {0}" -f $fullJob.RunbookName)
                $exception = $fullJob.Exception
                if($exception.Contains("Operation results in exceeding quota limits of Core"))
                {
                    Write-Verbose ("Adding quota Failed result for {0}" -f $fullJob.RunbookName)
                    $failureType = 'QuotaFailures'      
                    $quotaFailuresTotal++              
                }
                elseif($exception.Contains("Allocation failed. We do not have sufficient capacity for the requested VM size in this region."))
                {
                    Write-Verbose ("Adding Capacity Failed result for {0}" -f $fullJob.RunbookName)
                    $failureType = 'CapacityFailures'    
                    $capacityFailuresTotal ++          
                }
                elseif($knownFailuresList.Contains($fullJob.RunbookName)) 
                {
                    Write-Verbose ("Adding Known failure result for {0}" -f $fullJob.RunbookName)
                    $failureType = 'KnownFailures'
                    $knownFailuresTotal ++
                }
                else 
                {
                    Write-Verbose ("Adding other Failed result for {0}" -f $fullJob.RunbookName)
                    $failureType = 'OtherFailures'        
                    $otherFailuresTotal ++            
                }
                $failures[$failureType] += ("{0}: Failed</br>Exception: {1}</br>" -f $fullJob.RunbookName, $exception)
                #$results += ("{0}: <b>Failed</b></br>Exception:</br>{1}</br>" -f $fullJob.RunbookName, $exception)
                $verboseLogString = ""
                #$records = Get-AzureRmAutomationJobOutput -Id $job.JobId -ResourceGroupName $job.ResourceGroupName -AutomationAccountName $job.AutomationAccountName -Stream Any | Get-AzureRmAutomationJobOutputRecord
                #$records | ForEach-Object { if ($_.Value.Message -and !$_.Value.Message.StartsWith("Importing") -and !$_.Value.Message.StartsWith("Automation variable")) { $verboseLogString = $verboseLogString + $_.Value.Message + [Environment]::NewLine} } 
                #$results += ("Verbose Logs:</br><pre>{0}</pre></br>" -f [System.Net.WebUtility]::HtmlEncode($verboseLogString))                
                $failures[$failureType] += ("Powershell:</br><code>`$records = (Get-AzureRmAutomationJobOutput -Id {0} -ResourceGroupName {1} -AutomationAccountName {2} -Stream Any | Get-AzureRmAutomationJobOutputRecord).Summary</code></br></br>" -f $job.JobId, $job.ResourceGroupName, $job.AutomationAccountName)
                $jobsFailed++
            }            
            else
            {
                if($knownFailuresList.Contains($fullJob.RunbookName)) 
                {
                    Write-Verbose ("Adding Known test eviction result for {0}" -f $fullJob.RunbookName)                    
                    $failures['KnownTestSuspensions'] += ("{0}: Unknown</br>" -f $fullJob.RunbookName) 
                    $failures['KnownTestSuspensions'] += ("Powershell:</br><code>`$records = Get-AzureRmAutomationJobOutput -Id {0} -ResourceGroupName {1} -AutomationAccountName {2} -Stream Any | Get-AzureRmAutomationJobOutputRecord</code></br></br>" -f $job.JobId, $job.ResourceGroupName, $job.AutomationAccountName)
                    $knownEvictionsTotal ++              
                    $noKnownEvictions = $false
                }
                else 
                {
                    Write-Verbose ("Adding Unknown result for {0}, investigate" -f $fullJob.RunbookName)                
                    $unknownResults += ("{0}: Unknown</br>" -f $fullJob.RunbookName)  
                    $unknownResults += ("Powershell:</br><code>`$records = Get-AzureRmAutomationJobOutput -Id {0} -ResourceGroupName {1} -AutomationAccountName {2} -Stream Any | Get-AzureRmAutomationJobOutputRecord</code></br></br>" -f $job.JobId, $job.ResourceGroupName, $job.AutomationAccountName)
                    $noUnknownResults = $false   
                }           
            }
        }
    }       
    $jobsNotCompleted = $jobsCompleted - ($jobsPassed + $jobsFailed)
    $unknownEvictionsTotal = $jobsNotCompleted - $knownEvictionsTotal
    $stats = ("<p>Total: {0}</br>Passed: {1}</br>Failed: {2}   (Quota failures: {4}, Capacity failures: {5}, Known failures: {6}, Other failures: {7})</br>Suspended: {3}   (Known: {8}, Other: {9})</p>" `
                -f $jobsCompleted, $jobsPassed, $jobsFailed, $jobsNotCompleted, $quotaFailuresTotal, $capacityFailuresTotal, $knownFailuresTotal, $otherFailuresTotal, $knownEvictionsTotal, $unknownEvictionsTotal)
        
    $failedJobResults += ("</br><b>Quota limitation failures: {3}</b></br> {0} </br><b>Capacity limitation failures: {4}</b></br> {1} </br> <b>Other failures: {5}</b></br> {2} </br>" -f $failures['QuotaFailures'], $failures['CapacityFailures'], $failures['OtherFailures'], `
                                            $quotaFailuresTotal, $capacityFailuresTotal, $otherFailuresTotal)    
    if($noUnknownResults) 
    {
        $unknownResults += "n/a</br>"
    }    
    if($noKnownEvictions)
    {        
        #$failures['KnownTestSuspensions'] += ("n/a </br>")                   
    }          
    $knownIssues += ("</br><b>Known test evictions: {0}</b></br> {2} </br><b>Known test failures: {1}</b></br> {3}" -f `
                    $knownEvictionsTotal, $knownFailuresTotal, $failures['KnownTestSuspensions'], $failures['KnownFailures'])
     
    $resultsParagraph = ("<p>{0}</br>{1}</br>{2}</br>{3}</br></p>" -f $results, $unknownResults, $failedJobResults, $knownIssues)     
    $body = ("<body>{0}{1}{2}</body>" -f $stats, $azAutoLink, $resultsParagraph)        
    $subject = ("{4} ADE Automated Test Results {0}/{1}: Passed-{2} Failed-{3}" -f $today.Month, $today.Day, $jobsPassed, $jobsFailed, $environment)        
    Send-MailMessage -To $recipientArr -From $acctName -SmtpServer $server -Port $port -Credential $creds -Subject $subject -BodyAsHtml -Body $body -UseSsl    
    Write-Verbose "Today's test result email sent successfully"
}
catch
{
    Write-Error -Message $_
    Write-Error -Message $_.GetType()
    Write-Error -Message $_.Exception
    Write-Error -Message $_.Exception.StackTrace
    throw $_
}

Write-Verbose "END: Send-DailyResults"
