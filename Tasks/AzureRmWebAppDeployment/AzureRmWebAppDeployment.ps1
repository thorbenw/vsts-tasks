[CmdletBinding()]
param()

Trace-VstsEnteringInvocation $MyInvocation

try{

	# Get inputs.
	$WebAppName = Get-VstsInput -Name WebAppName -Require
    $WebAppType = Get-vstsInput -Name WebAppType 
	$DeployToSlotFlag = Get-VstsInput -Name DeployToSlotFlag -Require -AsBool
	$ResourceGroupName = Get-VstsInput -Name ResourceGroupName
	$SlotName = Get-VstsInput -Name SlotName
	$Package = Get-VstsInput -Name Package -Require
	$RemoveAdditionalFilesFlag = Get-VstsInput -Name RemoveAdditionalFilesFlag -AsBool
	$ExcludeFilesFromAppDataFlag = Get-VstsInput -Name ExcludeFilesFromAppDataFlag -AsBool
	$TakeAppOfflineFlag = Get-VstsInput -Name TakeAppOfflineFlag -AsBool
	$VirtualApplication = Get-VstsInput -Name VirtualApplication 
	$AdditionalArguments = Get-VstsInput -Name AdditionalArguments 
	$WebAppUri = Get-VstsInput -Name WebAppUri
	$SetParametersFile = Get-VstsInput -Name SetParametersFile

    #Defined constant webapp types
    $ASP_DOT_NET_4 = "ASPdotNet4"
    $ASP_DOT_NET_5 = "ASPdotNet5"

	# Initialize Azure.

	Import-Module $PSScriptRoot\ps_modules\VstsAzureHelpers_
	Initialize-Azure

	# Import the loc strings.
	Import-VstsLocStrings -LiteralPath $PSScriptRoot/Task.json

	$WebAppUri = $WebAppUri.Trim()
	$Package = "$Package".Trim('"').Trim()

	if( [string]::IsNullOrEmpty($Package) ){
		Throw (Get-VstsLocString -Key "Invalidwebapppackagepathprovided")
	}

	$SetParametersFile = "$SetParametersFile".Trim('"').Trim()


	# Load all dependent files for execution
	. $PSScriptRoot/AzureUtility.ps1
	. $PSScriptRoot/Utility.ps1
	. $PSScriptRoot/FindInstalledMSDeploy.ps1

	# Importing required version of azure cmdlets according to azureps installed on machine
	$azureUtility = Get-AzureUtility

	Write-Verbose  "Loading $azureUtility"
	. $PSScriptRoot/$azureUtility -Force

	#### MAIN EXECUTION OF AZURERM WEBAPP DEPLOYMENT TASK BEGINS HERE ####

	# Get msdeploy.exe path
	$msDeployExePath = Get-MsDeployExePath

	if( $WebAppType -eq $ASP_DOT_NET_4 )
    {
        # Ensure that at most a package (.zip) file is found
        $packageFilePath = Get-SingleFilePath -file $Package
    }
    elseif( $WebAppType -eq $ASP_DOT_NET_5 )
    {

        $packageFilePath  = "$package\wwwroot"

        if( ! ( ( Test-Path $package ) -and (Test-Path $packageFilePath) ) )
        {
            throw (Get-VstsLocString -Key Specifiedpath0doesntexist -ArgumentList $package)
        }

    }

    # Since the SetParametersFile is optional, but it's a FilePath type, it will have the value System.DefaultWorkingDirectory when not specified
    if( $SetParametersFile -eq $env:SYSTEM_DEFAULTWORKINGDIRECTORY -or $SetParametersFile -eq [String]::Concat($env:SYSTEM_DEFAULTWORKINGDIRECTORY, "\" ) -or [string]::IsNullOrEmpty($SetParametersFile) ){
	   $setParametersFilePath = ""
    } else {
       $setParametersFilePath = Get-SingleFilePath -file $SetParametersFile
    }

	# Get destination azureRM webApp connection details
	$azureRMWebAppConnectionDetails = Get-AzureRMWebAppConnectionDetails -webAppName $WebAppName -deployToSlotFlag $DeployToSlotFlag `
																		   -resourceGroupName $ResourceGroupName -slotName $SlotName

	# webApp Name to be used in msdeploy command
	$webAppNameForMSDeployCmd = Get-WebAppNameForMSDeployCmd -webAppName $WebAppName -deployToSlotFlag $DeployToSlotFlag -slotName $SlotName

	# Construct arguments for msdeploy command
	if( $WebAppType -eq $ASP_DOT_NET_4   )
    {
         $msDeployCmdArgs = Get-MsDeployCmdArgs -packageFile $packageFilePath -webAppNameForMSDeployCmd $webAppNameForMSDeployCmd -azureRMWebAppConnectionDetails $azureRMWebAppConnectionDetails -removeAdditionalFilesFlag $RemoveAdditionalFilesFlag `
                                       -excludeFilesFromAppDataFlag $ExcludeFilesFromAppDataFlag -takeAppOfflineFlag $TakeAppOfflineFlag -virtualApplication $VirtualApplication -AdditionalArguments $AdditionalArguments `
                                       -setParametersFile $setParametersFilePath
    }
    elseif( $WebAppType -eq $ASP_DOT_NET_5 )
    {
         $msDeployCmdArgs = Get-MsDeployAspDotNet5CmdArgs -wwwRootDir $packageFilePath -webAppNameForMSDeployCmd $webAppNameForMSDeployCmd -azureRMWebAppConnectionDetails $azureRMWebAppConnectionDetails -removeAdditionalFilesFlag $RemoveAdditionalFilesFlag `
                                       -excludeFilesFromAppDataFlag $ExcludeFilesFromAppDataFlag -takeAppOfflineFlag $TakeAppOfflineFlag -AdditionalArguments $AdditionalArguments
    }

	# Deploy azureRM webApp using msdeploy Command
	Run-MsDeployCommand -msDeployExePath $msDeployExePath -msDeployCmdArgs $msDeployCmdArgs

	# Get azure webapp hosted url
	$azureWebsitePublishURL = Get-AzureRMWebAppPublishUrl -webAppName $WebAppName -deployToSlotFlag $DeployToSlotFlag `
																		   -resourceGroupName $ResourceGroupName -slotName $SlotName

	# Publish azure webApp url
	Write-Host (Get-VstsLocString -Key "WebappsuccessfullypublishedatUrl0" -ArgumentList $azureWebsitePublishURL)

	# Set ouput vairable with azureWebsitePublishUrl
	if(-not [string]::IsNullOrEmpty($WebAppUri))
	{
	
		if( [string]::IsNullOrEmpty($azureWebsitePublishURL))
		{
			Throw (Get-VstsLocString -Key "Unabletoretrievewebapppublishurlforwebapp0" -ArgumentList $webAppName)
		}
	
		Set-VstsTaskVariable -Name $WebAppUri -Value $azureWebsitePublishURL
	}

	Write-Verbose "Completed AzureRM WebApp Deployment Task"

} finally {
    Trace-VstsLeavingInvocation $MyInvocation
}



