#Ensures required software exists.
function ValidateRequiredSoftwareExists()
{
   if(!(Test-Path "${env:ProgramFiles(x86)}\Microsoft Visual Studio 14.0\Common7\IDE\Extensions\Microsoft\SQLDB\DAC\130") -or (!(Test-Path "${env:ProgramFiles(x86)}\Microsoft SQL Server")))
    {
        Throw "SOFTWARE ERROR: Visual Studio 2015, SSDT 2016 and SSMS are required to deploy this code.";
    }
}