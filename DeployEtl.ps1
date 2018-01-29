#Arguments override config.ini params.
Param(
    [String] $argEnvironment,
    [String] $argIspacPath,
    [String] $argsqlServerNode,
    [String] $argCatalogName
    );

# Change working directory
$rootDir = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent;
Push-Location $rootDir;

try 
{
	.("$rootDir\Includes\functionGetIniContent.ps1");
    .("$rootDir\Includes\functionWriteLog.ps1");
    .("$rootDir\Includes\functionSoftwareValidation.ps1");
    .("$rootDir\Includes\functionDeployEtl.ps1");
	.("$rootDir\Includes\functionExecuteSqlQuery.ps1");
	Import-Module SqlPs -DisableNameChecking;
}
catch 
{
    Throw "A fatal error has occured while loading supporting PowerShell Scripts/Modules";
}

$tabChar = "`t";
$etlEnvironmentName="Wescot";
$parameters = New-Object System.Object
$parameters | Add-Member -type NoteProperty -Name iniFile -Value "$rootDir\config.ini";
$appSettings = Get-IniContent $parameters.iniFile;
$parameters | Add-Member -type NoteProperty -Name username -Value $env:USERNAME;
$adSearch = [adsisearcher]"(samaccountname=$($parameters.username))";
$parameters | Add-Member -type NoteProperty -Name usersEmail -Value $adSearch.FindOne().Properties.mail;
$parameters | Add-Member -type NoteProperty -Name mailTo -Value $appSettings["Misc"]["DeploymentMailTo"].Trim();
$parameters | Add-Member -type NoteProperty -Name smtpServer -Value $appSettings["Misc"]["smtpServer"].Trim();
$parameters | Add-Member -type NoteProperty -Name artefactsDirectory -Value $(if($argIspacPath) { $argIspacPath } else { $rootDir + "\" + $appSettings["Misc"]["ArtefactsDirectory"] }).Trim();
$parameters | Add-Member -type NoteProperty -Name availableEnvironments -Value $appSettings["DeployableObjects"]["Environments"].split(",");
$parameters | Add-Member -type NoteProperty -Name runWithNoPrompt -Value $appSettings["Misc"]["RunWithNoPrompt"].Trim();
$parameters | Add-Member -type NoteProperty -Name ispacLogFile -Value "$rootDir\Logs\ispacLog.txt";
$parameters | Add-Member -type NoteProperty -Name sqlLogFile -Value "$rootDir\Logs\sqlLog.txt";
$parameters | Add-Member -type NoteProperty -Name paramlLogFile -Value "$rootDir\Logs\paramLog.txt";

writeLogLine "Script Started`n";

writeLogLine "whoami: [$($parameters.username)]";

if($parameters.availableEnvironments -contains $argEnvironment -or $argEnvironment -eq $parameters.runWithNoPrompt)
{
    writeLogLine "Environment Input: [$argEnvironment]";

    $parameters | Add-Member -type NoteProperty -Name databaseServer -Value $(if($argsqlServerNode) { $argsqlServerNode.Trim() } else { $appSettings["DatabaseServers"][$argEnvironment.Trim()] });
    $parameters | Add-Member -type NoteProperty -Name etlCatalogName -Value $(if($argCatalogName) { $argCatalogName.Trim() } else { $appSettings["EtlCatalogName"][$argEnvironment.Trim()] });

    writeLogLine "Parameters: [IniFile: $($parameters.iniFile)], [dbServer: $($parameters.databaseServer)], [ArtefactDirectory: $($parameters.artefactsDirectory)], ETLEnvironameName: [$etlEnvironmentName], ETLCatalog: [$($parameters.etlCatalogName)]`n";

    <# Required Software Doesnt Exist #>
    $softwareExists=ValidateRequiredSoftwareExists;
  
    <# Deployable ISPAC Objects #>
    $ispacs = Get-ChildItem $($parameters.artefactsDirectory) -Filter *.ispac;
	$sqls = Get-ChildItem $($parameters.artefactsDirectory) -Filter *.sql;

	if($ispacs.Count -eq 0)
	{
		Throw "Fatal Error: No deployment files were found within the artefact directory [$parameters.artefactsDirectory].";
	}
    
    if($argEnvironment -ne $parameters.runWithNoPrompt)
    {
        writeLogLine "Prompting for user confirmation.";
        $title = "Deployment confirmation?";
        $prompt = "Confirm deployment of $($ispacs.Name) to $($argEnvironment) [A]bort or [C]continue?";
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
    
    writeLogLine "Starting ETL deployment to $argEnvironment";
    
	writeLogLine "$($tabChar)DEBUG: found $($ispacs.count) ispacs for deployment.";

	<# This section deploys all ISPAC files found in artefact directory #>
    $i = 0;
    foreach($ispac in $ispacs)
    {
        $i++;
        $status = $("Database " + $i + " of " + $ispacs.count);
        $projectName = $ispac.Name.Replace(".ispac","");
        Write-Progress -Activity 'Deploying ETL Packages' -CurrentOperation $ispac.Name -Status $status -PercentComplete (($i / $ispacs.count) * 100);
		$fullIspacPath = $parameters.artefactsDirectory + "\" + $ispac.Name;       
		deployEtlPackage $projectName $fullIspacPath $parameters.databaseServer $parameters.EtlCatalogName > $parameters.ispacLogFile;

		cat $parameters.ispacLogFile;
	
		writeLogLine "Starting ETL Parameter Binding to $argEnvironment";


		$paramFile = Get-ChildItem $($parameters.artefactsDirectory) -Filter "$projectName.bind";

		if($paramFile.Count -eq 0)
		{
			Throw "Fatal Error: No parameter binding file was found within the artefact directory [$parameters.artefactsDirectory].";
		}

		$fullParamPath = $($parameters.artefactsDirectory + "\" + $paramFile.Name);
		writeLogLine "$($tabChar)$($tabChar)DEBUG: Applying Parameter File [$fullParamPath]";

		$lines = get-content $fullParamPath;

		foreach($line in $lines)
		{
			writeLogLine "Binding parameter [$line]";
			$bindingQuery="EXEC custom.ParameterBinding  @environmentName = '$etlEnvironmentName', @catalogFolder = '$($parameters.etlCatalogName)', @project_name = '$projectName', @parameterKey='$line'";
			ExecuteSqlQuery $($parameters.databaseServer) "SSISDB" $bindingQuery > $parameters.paramlLogFile;

			cat $parameters.paramlLogFile;
		}
		
    }

	writeLogLine "Starting SQL Script deployment to [$argEnvironment]";
	
	if($sqls.Count -eq 0)
	{
		writeLogLine "$($tabChar)No SQL deployment files were found within the artefact directory [$parameters.artefactsDirectory].";
	}

	writeLogLine "$($tabChar)DEBUG: found $($sqls.count) SQL scripts for deployment.";

	<# This section applys all sql files found in artefact directory #>
	$i = 0;
	foreach($sqlFile in $sqls)
	{
		$i++;
        $status = $("SQL Script " + $i + " of " + $sqls.count);
        Write-Progress -Activity 'Deploying SQL Scripts' -CurrentOperation $sqlFile.Name -Status $status -PercentComplete (($i / $sqls.count) * 100);
		$fullSqlPath = $($parameters.artefactsDirectory + "\" + $sqlFile.Name);
		writeLogLine "$($tabChar)DEBUG: Applying $fullSqlPath";
		
		Invoke-Sqlcmd -InputFile $fullSqlPath -ServerInstance $parameters.databaseServer -ErrorAction 'Stop' -Verbose -QueryTimeout 600 > $parameters.sqlLogFile;
		cat $parameters.sqlLogFile;
		writeLogLine "$($tabChar)$($sqlFile.Name) Successfull";
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