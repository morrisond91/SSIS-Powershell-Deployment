#executes a query and populates the $datatable with the data
function ExecuteSqlQuery ([string] $Server, [string] $Database, [string] $SQLQuery, [bool] $return)
{
    $Connection = New-Object System.Data.SQLClient.SQLConnection
    $Connection.ConnectionString = "server='$Server';database='$Database';trusted_connection=true;"
	writeLogLine "SQLDEBUG: Connection String [$($Connection.ConnectionString)]";
    $Connection.Open()
    $Command = New-Object System.Data.SQLClient.SQLCommand
    $Command.Connection = $Connection
    $Command.CommandText = $SQLQuery
    $Reader = $Command.ExecuteReader()
  
    if($return = 1)
    {
        while ($Reader.Read())
        {
             $output = "";
             #Iterate through Rows
              for ($i = 0; $i -lt $Reader.FieldCount; $i++) 
              {
                  $output += " | " + $Reader.GetValue($i) 
              }
            $output + "`r"
        }
    }

    $Connection.Close()
}