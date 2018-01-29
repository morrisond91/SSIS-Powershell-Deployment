#xdeploys ETL packages
function deployETLPackage ([string] $projectName, [string] $packageIspacLocation, [string] $serverName, [string] $catalogFolderName)
{
    #Try to load 2014 version of sql assembly, otherwise load previous version.
    try
    {
        Add-Type -AssemblyName "Microsoft.SqlServer.Management.IntegrationServices, Version=12.0.0.0, Culture=neutral, PublicKeyToken=89845dcd8080cc91";
    }
    catch
    {
        Add-Type -AssemblyName "Microsoft.SqlServer.Management.IntegrationServices, Version=11.0.0.0, Culture=neutral, PublicKeyToken=89845dcd8080cc91";
    }

    $sqlConnectionString = "Data Source=$serverName;Initial Catalog=master;Integrated Security=SSPI";
    writeLogLine "$($tabChar)DEBUG: $sqlConnectionString";
    $sqlConnection = New-Object System.Data.SqlClient.SqlConnection $sqlConnectionString;
    $ssisServer = New-Object Microsoft.SqlServer.Management.IntegrationServices.IntegrationServices $sqlConnection;
    $ssisCatalogName = "SSISDB";
    $ssisCatalog = $ssisServer.Catalogs[$ssisCatalogName];
    $ssisFolderName = $catalogFolderName;

    if (-not $ssisCatalog)
    {
        Throw "$($tabChar)The SSIS catalog [$ssisCatalogName] does not exist on server [$serverName]. Please create it manually!";
    }
    
    if ($ssisCatalog.Folders.Contains($ssisFolderName))
    {
        writeLogLine "$($tabChar)[$ssisFolderName] folder found on catalog [$ssisCatalogName], skipping creation step.";
        $ssisFolder = $ssisCatalog.Folders[$ssisFolderName];
    }
    else
    {
        writeLogLine "$($tabChar)[$ssisFolderName] folder not found on catalog [$ssisCatalogName] and is being created.";
        $ssisFolderDescription = "Created with PowerShell Deployment Wizard";
        $ssisFolder = New-Object Microsoft.SqlServer.Management.IntegrationServices.CatalogFolder($ssisCatalog, $ssisFolderName, $ssisFolderDescription);
        $ssisFolder.Create();
    }

    writeLogLine "$($tabChar)Deploying [$projectName] to [$serverName] using artefact [$packageIspacLocation]"; 

    try
    {
        [byte[]] $ssisProjectFile = [System.IO.File]::ReadAllBytes("$packageIspacLocation");

        $ssisFolder.DeployProject($projectName, $ssisProjectFile);
        writeLogLine "$($tabChar)$projectName deployment has completed successfully, please perform unit test.";
    }
    catch
    {
		Throw "$($tabChar)A error has occured during the ETL deployment.";
    }
}