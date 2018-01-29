#Arguments override config.ini params.
Param(
	[String] $argEnvironment,
    [String] $argSqlServerNode,
    [String] $argCatalogName,
	[String] $argParameters #params argument should always be last item
    );

# Change working directory
$rootDir = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent;
Push-Location $rootDir;

try 
{
	.("$rootDir\Includes\functionGetIniContent.ps1");
    .("$rootDir\Includes\functionWriteLog.ps1");
    .("$rootDir\Includes\functionExecuteSqlQuery.ps1");
}
catch 
{
    Throw "A fatal error has occured while loading supporting PowerShell Scripts/Modules";
}

$tabChar = "`t";
$etlEnvironmentName="Wescot";
$parameters = New-Object System.Object;
$parameters | Add-Member -type NoteProperty -Name iniFile -Value "$rootDir\config.ini";
$appSettings = Get-IniContent $parameters.iniFile;
$parameters | Add-Member -type NoteProperty -Name username -Value $env:USERNAME;
$parameters | Add-Member -type NoteProperty -Name envParameters -Value $(if($argParameters) { $argParameters } else { $appSettings["EnvironmentParameters"][$argEnvironment.Trim()] });
$parameters | Add-Member -type NoteProperty -Name availableEnvironments -Value $appSettings["DeployableObjects"]["Environments"].split(",");
$parameters | Add-Member -type NoteProperty -Name runWithNoPrompt -Value $appSettings["Misc"]["RunWithNoPrompt"].Trim();

writeLogLine "Script Started`n";

writeLogLine "whoami: [$($parameters.username)]";

if($parameters.availableEnvironments -contains $argEnvironment -or $argEnvironment -eq $parameters.runWithNoPrompt)
{
    writeLogLine "Environment Input: [$argEnvironment]";

    $parameters | Add-Member -type NoteProperty -Name databaseServer -Value $(if($argSqlServerNode) { $argSqlServerNode.Trim() } else { $appSettings["DatabaseServers"][$argEnvironment.Trim()] });
    $parameters | Add-Member -type NoteProperty -Name etlCatalogName -Value $(if($argCatalogName) { $argCatalogName.Trim() } else { $appSettings["EtlCatalogName"][$argEnvironment.Trim()] });

    writeLogLine "Parameters: [IniFile: $($parameters.iniFile)], [dbServer: $($parameters.databaseServer)], [Environment Parameters: $($parameters.envParameters)], ETLEnvironameName: [$etlEnvironmentName], ETLCatalog: [$($parameters.etlCatalogName)]`n";

    if($argEnvironment -ne $parameters.runWithNoPrompt)
    {
        writeLogLine "Prompting for user confirmation.";
        $title = "Deployment confirmation?";
        $prompt = "Confirm deployment of parameters to $($argEnvironment) [A]bort or [C]continue?";
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

	if($parameters.envParameters -eq 0)
	{
		Throw "No parameters found to deploy.";
	}

	writeLogLine "DEBUG: found $($parameters.envParameters.count) parameters to deploy.";

	writeLogLine "DEBUG: Applying parambinding stored procedure";
	
	<#
		Check if stored procedure exists then drop it, if schema doesnt exist, create it.
	#>
	$checkAndDropBindingSproc="
		IF NOT EXISTS (SELECT name FROM sys.schemas WHERE name = N'custom')
		BEGIN
			EXEC('CREATE SCHEMA [custom] AUTHORIZATION [dbo]');
			PRINT 'Creating custom schema.'
		END 
		IF OBJECT_ID('custom.ParameterBinding', 'P') IS NOT NULL
		BEGIN
			DROP PROC custom.ParameterBinding
			PRINT 'Stored proc ParameterBinding found and is being dropped.'
		END
		PRINT 'Adding ParameterBinding.'";

	ExecuteSqlQuery $($parameters.databaseServer) "SSISDB" $checkAndDropBindingSproc;

	<#
		Apply stored procedure.
	#>
	$createBindingStoredProc = "
	-- =============================================
	-- Author:		David Morrison
	-- Create date: 26/01/2018
	-- Description:	Binds environment parameters to project parameters.
	-- =============================================
	CREATE PROCEDURE custom.ParameterBinding
		@environmentName	NVARCHAR(MAX),
		@catalogFolder		NVARCHAR(MAX),
		@project_name		NVARCHAR(MAX),
		@parameterKey		NVARCHAR(500)

	AS
	BEGIN

		DECLARE @reference_id	BIGINT	

		IF NOT EXISTS (SELECT * 
						FROM catalog.environment_references A
						INNER JOIN catalog.projects B ON A.project_id = B.project_id
						WHERE B.name = @project_name
						AND environment_name = @environmentName AND A.environment_folder_name = @catalogFolder)
		BEGIN
			PRINT 'No project to environment reference was found, we are adding it now.'
			EXEC [SSISDB].[catalog].[create_environment_reference] 
			@environment_name=@environmentName,
			@environment_folder_name=@catalogFolder, 
			@reference_id=@reference_id OUTPUT, 
			@project_name=@project_name, 
			@folder_name=@catalogFolder, 
			@reference_type=A
		END
		ELSE
		BEGIN
			PRINT 'Reference found, nothing to do.'
		END

		PRINT 'Binding parameters to project.'
		
		DECLARE @paramValue SQL_VARIANT = CONVERT(sql_variant,@parameterKey);

		EXEC [SSISDB].[catalog].[set_object_parameter_value] 
			@object_type=20, 
			@parameter_name=@parameterKey,
			@object_name=@project_name, 
			@folder_name=@catalogFolder, 
			@project_name=@project_name, 
			@value_type=R, 
			@parameter_value=@paramValue;
		END";

	ExecuteSqlQuery $($parameters.databaseServer) "SSISDB" $createBindingStoredProc;

	writeLogLine "DEBUG: Checking for $etlEnvironmentName environment on $($parameters.etlCatalogName) on $($parameters.databaseServer).";
	
	$environmentExistsQuery="
			
			DECLARE 
				@environment				NVARCHAR(MAX) = '$etlEnvironmentName',
				@environmentDescription		NVARCHAR(MAX) = 'Created via TFS automated release.',
				@catalogFolder				NVARCHAR(MAX) = '$($parameters.etlCatalogName)'

			IF NOT EXISTS (SELECT *
			   FROM catalog.environments A
			   INNER JOIN catalog.folders B ON A.folder_id = B.folder_id
			   WHERE A.name = @environment AND B.name = @catalogFolder)
				BEGIN
					PRINT 'Environment not found, and is being created.'
					EXEC [catalog].[create_environment] @environment_name = @environment, @environment_description = @environmentDescription, @folder_name = @catalogFolder;
				END
			ELSE

				BEGIN
					PRINT 'Environment already exists.'
				END";

	ExecuteSqlQuery $($parameters.databaseServer) "SSISDB" $environmentExistsQuery;

	$json = ConvertFrom-Json -InputObject $parameters.envParameters;
	$jsonProperties = $json | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name

	ForEach($property in $jsonProperties) 
	{
		writeLogLine "DEBUG: Apply $property=$($json.$property) to $etlEnvironmentName on $($parameters.etlCatalogName) for $($parameters.databaseServer)";

		$createOrUpdateParameterQuery="
			DECLARE 
				@environmentId			BIGINT,
				@environmentName		NVARCHAR(MAX) = '$etlEnvironmentName',
				@catalogFolder			NVARCHAR(MAX) = '$($parameters.etlCatalogName)',
				@parameterName			NVARCHAR(MAX) = '$property',
				@parameterValue			SQL_VARIANT	  = '$($json.$property)',
				@parameterDescription	NVARCHAR(MAX) = 'Added via TFS automated release process.',
				@paramId				BIGINT,
				@currentValue			SQL_VARIANT

			/* Bind environment ID */
			SELECT @environmentId = A.environment_id 
			FROM catalog.environments A 
			INNER JOIN catalog.folders B ON A.folder_id = B.folder_id
			WHERE A.name = @environmentName AND B.name = @catalogFolder

			IF NOT EXISTS (SELECT variable_id FROM catalog.environment_variables WHERE Name = @parameterName AND environment_id = @environmentId)
			BEGIN
				/* Parameter doesnt exist, so needs adding */
				INSERT INTO internal.environment_variables (environment_id,name,description, type, value,sensitive, base_data_type)
				VALUES (@environmentId, @parameterName,@parameterDescription,N'string',@parameterValue, 0,  N'nvarchar')
				PRINT 'SUCCESS - environment variable created for DB_IandE_OLEDB.'
			END
			ELSE IF EXISTS (SELECT variable_id FROM catalog.environment_variables WHERE Name = @parameterName AND environment_id = @environmentId)
			BEGIN
				/* Parameter exists, so check if it has an updated value. */
				SELECT @paramId=variable_id,@currentValue = value 
				FROM catalog.environment_variables 
				WHERE Name = @parameterName 
				AND environment_id = @environmentId

				/* Current value matches release value? */
				IF(@currentValue <> @parameterValue)
				BEGIN 
					PRINT 'Values are different for for parameter: ' + CONVERT(NVARCHAR(MAX),@paramId)

					UPDATE internal.environment_variables 
					SET value = @parameterValue 
					WHERE variable_id = @paramId
				END
				ELSE
					PRINT 'Values match, nothing to do.'
			END";

		ExecuteSqlQuery $($parameters.databaseServer) "SSISDB" $createOrUpdateParameterQuery;
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