#Arguments override config.ini params.
Param(
	[String] $argEnvironment,
	[String] $argArtefactDirectory,
	[String] $argBaseDirectory
    );

# Change working directory
$rootDir = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent;
Push-Location $rootDir;

try 
{
	.("$rootDir\Includes\functionGetIniContent.ps1");
    .("$rootDir\Includes\functionWriteLog.ps1");
}
catch 
{
    Throw "A fatal error has occured while loading supporting PowerShell Scripts/Modules";
}

$tabChar = "`t";
$parameters = New-Object System.Object
$parameters | Add-Member -type NoteProperty -Name iniFile -Value "$rootDir\config.ini";
$appSettings = Get-IniContent $parameters.iniFile;
$parameters | Add-Member -type NoteProperty -Name username -Value $env:USERNAME;
$parameters | Add-Member -type NoteProperty -Name artefactsDirectory -Value $(if($argArtefactDirectory) { $argArtefactDirectory } else { $rootDir + "\" + $appSettings["Misc"]["ArtefactsDirectory"] }).Trim();
$parameters | Add-Member -type NoteProperty -Name availableEnvironments -Value $appSettings["DeployableObjects"]["Environments"].split(",");
$parameters | Add-Member -type NoteProperty -Name runWithNoPrompt -Value $appSettings["Misc"]["RunWithNoPrompt"].Trim();

writeLogLine "Script Started`n";
writeLogLine "whoami: [$($parameters.username)]";

if($parameters.availableEnvironments -contains $argEnvironment -or $argEnvironment -eq $parameters.runWithNoPrompt)
{
	writeLogLine "Environment Input: [$argEnvironment]";
	$directoryReleases = Get-ChildItem $parameters.artefactsDirectory -Filter *.dir;
	$parameters | Add-Member -type NoteProperty -Name baseDirectory -Value $(if($argBaseDirectory) { $argBaseDirectory } else { $appSettings["FolderShares"][$argEnvironment.Trim()] }).Trim();
	
	writeLogLine "Parameters: [IniFile: $($parameters.iniFile)], [BaseDrive: $($parameters.baseDirectory)], [ArtefactDirectory: $($parameters.artefactsDirectory)]`n";

	if($directoryReleases.Count -eq 0)
	{
		Throw "No directory deployment files were found within the artefact directory [$($parameters.artefactsDirectory)].";
	}

	writeLogLine "$($tabChar)DEBUG: found $($directoryReleases.count) directory files for deployment.";

	if($argEnvironment -ne $parameters.runWithNoPrompt)
    {
        writeLogLine "Prompting for user confirmation.";
        $title = "Deployment confirmation?";
        $prompt = "Confirm deployment of directories to $environment [A]bort or [C]continue?";
        $abort = New-Object System.Management.Automation.Host.ChoiceDescription "&Abort","Aborts the operation";
        $continue = New-Object System.Management.Automation.Host.ChoiceDescription "&Continue","Continues the operation";
        $options = [System.Management.Automation.Host.ChoiceDescription[]] ($abort,$continue);
        $choice = $host.ui.PromptForChoice($title, $prompt, $options, 0);
        writeLogLine "$($tabChar)User selected: $choice";

        if($choice -eq 0)
        {
            exit;
        } 
    }

	foreach($directoryRelease in $directoryReleases)
	{
		$fullReleaseDirPath = $parameters.artefactsDirectory + "\" + $directoryRelease.Name;
		writeLogLine "$($tabChar)DEBUG: getting content of [$($directoryRelease.Name)], fullpath=[$fullReleaseDirPath].";
		$lines = Get-Content $fullReleaseDirPath;
		writeLogLine "$($tabChar)$($tabChar)DEBUG: Lines=[$($lines.Count)].";
	
		foreach($line in $lines) 
		{
			$chkDirPath = $parameters.baseDirectory + "\" + $line;

			If (Test-Path $chkDirPath)
			{
				writeLogLine "$($tabChar)DEBUG: Directory Found [$chkDirPath], nothing to do.";
			}
			else
			{
				writeLogLine "$($tabChar)DEBUG: Directory Not Found [$chkDirPath], being created.";
				md -Path $chkDirPath;
			}
		}
	}
}
else
{
    writeLogLine "Invalid environment input '"$argEnvironment"' please try again using one of the following: ";
    
    foreach($availableEnvironment in $parameters.availableEnvironments)
    { 
        writeLogLine "$($tabChar)" $availableEnvironment;
    }
}

writeLogLine "Script Finished";