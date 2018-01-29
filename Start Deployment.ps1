<# UI FOR MANUAL TRIGGER#>

$rootDir = $PSScriptRoot;
Push-Location $rootDir;
Clear-Host
$environmentTitle = 'ETL Deployment Wizard';
$environmentMessage = 'Please Select the environment that you are deploying to.';
$local = New-Object System.Management.Automation.Host.ChoiceDescription "&Local","Deploy to local";
$dev = New-Object System.Management.Automation.Host.ChoiceDescription "&Development","Deploy to Dev";

$environmentOptions = [System.Management.Automation.Host.ChoiceDescription[]]@($local,$dev);
$environmentResult = $host.ui.PromptForChoice($environmentTitle,$environmentMessage,$environmentOptions,0);

#Determines which option was selected from Env UI.
switch ($environmentResult)
{
    0 { $environment = "Local";}
    1 { $environment = "Development"; }
}

#.\Deploy.ps1 $environment

# END MANUAL TRIGGER.

# AUTOMATED TRIGGER.
#.\Deploy.ps1 "automated" "C:\Users\morrisond\source\repos\EtlMigrationCards\MigrationCards\MigrationCards\bin\Development" "wcs-d-etl1,65001" "Sample";

.\DeployEtl.ps1 "Development"