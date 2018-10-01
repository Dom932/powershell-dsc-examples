
#Example DCS config to install a single or multiple SQL instances on a server
#WIP
Configuration SQLServer2017Install
{
    [CmdletBinding()]
    param()

    Import-DscResource -ModuleName PSDesiredStateConfiguration, SQLServerDSC

    Node $AllNodes.NodeName
    {

        #Loop arround each instance for a Node
        foreach ($instance in $Node.instances)
        {

            #Set the Features to be installed to uppercase
            $instance.Features = $instance.Features.ToUpper()

            #Verify if SQL Managament Studio ("SSMS" and "ADV_SSMS") are not selected features. SQL Server 2016 and above 
            #Require this to be installed using a seprate package.
            if( ($instance.Features -contains 'SSMS') -or ($instance.Features -contains 'ADV_SSMS') -or ($instance.Features -contains 'RS')  )
            {
                $error = 'SQLServer 2016 and above installer, no longer installes SSMS, ADV_SSMS, RS. This is installed with another package'
                
                Log Log-Features
                {
                    Message = $error
                }

                Throw $error

            }

            if([string]::IsNullOrEmpty($instance.ASServerMode))
            {
                #If $instance.ASServerMode is not set, set it to SQL 2017 default of TABULAR.
                #SQLSetup requires this to be set even if not installing AS
                $instance.ASServerMode = 'TABULAR'
            }
            
            #Install SQL Server
            SqlSetup "SQLSetup-$($instance.InstanceName)"
            {
                #Source path to SQL installer
                SourcePath = $Node.SourcePath

                #Instance Name
                InstanceName = $instance.InstanceName

                #Features to be installed
                Features = $instance.Features

                #SQL Engine Servivce Account
                SQLSvcAccount = $instance.SQLSvcAccount

                #SQL Agent Service Account
                AgtSvcAccount = $instance.AgtSvcAccount

                #Reporting Services Service Account
                #SQL 2017 install package does not include Reporting Services. Seprate Package
                #RSSvcAccount = $instance.RSServiceAccount
                
                #Analysis Services Servivce Account
                ASSvcAccount  = $instance.ASSvcAccount

                #Integration Services Servivce Account
                ISSvcAccount  = $instance.ISSvcAccount

                #Array of Admin Accounts
                SQLSysAdminAccounts = $instance.SQLSysAdminAccounts

                #Array of Analysis Services Admin Accounts
                ASSysAdminAccounts = $instance.ASSysAdminAccounts 
               
                #Set SecurityMode - Windows or SQL
                #TODO looks to be an issue with the module. Needs investigating
                #SecurityMode = 'Windows'

                #TODO - Determin correct startup type
                #BrowserSvcStartupType = 'Automatic'

                #Disable update search
                UpdateEnabled = $false

                #SQL Collation
                SQLCollation = $instance.SQLCollation

                #Collation for Analysis Services
                ASCollation  = $instance.ASCollation 
                               
                # Server mode for SQL Server Analysis Services instance. 
                ASServerMode =  $instance.ASServerMode

                #Install path
                InstallSharedDir = $Node.InstallSharedDir
                InstallSharedWOWDir = $Node.InstallSharedWOWDir
                InstanceDir = $Node.InstanceDir

                #SQL ENGINE db path
                InstallSQLDataDir = $instance.InstallSQLDataDir
                SQLUserDBDir = $instance.SQLUserDBDir
                SQLUserDBLogDir = $instance.SQLUserDBLogDir
                SQLTempDBDir = $instance.SQLTempDBDir
                SQLTempDBLogDir = $instance.SQLTempDBLogDir
                SQLBackupDir = $instance.SQLBackupDir

                #Analysis Services db path
                ASDataDir = $instance.ASDataDir
                ASLogDir = $instance.ASLogDir
                ASBackupDir = $instance.ASBackupDir
                ASTempDir = $instance.ASTempDir
                ASConfigDir = $instance.ASConfigDir

            }

            #Configure TCP Port

            if($instance.TcpDynamicPort)
            {
                #Configure SQL server to be Dynamic
                SQLServerNetwork "SQLNetworking-$($instance.InstanceName)"
                {
                    InstanceName = $instance.InstanceName
                    ProtocolName = 'tcp'
                    IsEnabled = $true
                    RestartService = $restartService
                    TcpDynamicPort = $instance.TcpDynamicPort
                    DependsOn = "[SqlSetup]SQLSetup-$($instance.InstanceName)"
    
                }

                Log "SQLNetworking-$($instance.InstanceName)-Log"
                {
                    Message = "[$instance.InstanceName] - Configured to use Dynamic Ports"
                    DependsOn = "[SQLServerNetwork]SQLNetworking-$($instance.InstanceName)"
                }

            }
            else
            {
                #Configure SQL server to be Dynamic
                SQLServerNetwork "SQLNetworking-$($instance.InstanceName)"
                {
                    InstanceName = $instance.InstanceName
                    ProtocolName = 'tcp'
                    IsEnabled = $true
                    RestartService = $restartService
                    TcpDynamicPort = $instance.TcpDynamicPort
                    TcpPort = $instance.TcpPort
                    DependsOn = "[SqlSetup]SQLSetup-$($instance.InstanceName)"
    
                }

                Log "SQLNetworking-$($instance.InstanceName)-Log"
                {
                    Message = "[$instance.InstanceName] - Configured to use Static Port: $instance.TcpPort"
                    DependsOn = "[SQLServerNetwork]SQLNetworking-$($instance.InstanceName)"
                }

            }
           
            #Determin the require firewall configuration
            
            $fwSupportedFeatures = "SQLENGINE","AS","RS","IS"
            $fwFeatures = ($instance.Features.Split(",") | Where-Object {$fwSupportedFeatures -contains $_}) -join ","

            #If $fwFeatures is not null, then apply required firewall configuration
            if($fwFeatures)
            {           

                #Configure firewall
                SqlWindowsFirewall "SQLServerFirewall-$($instance.InstanceName)"
                {

                    Ensure = 'Present'
                    Features = $fwFeatures
                    InstanceName = $instance.InstanceName
                    SourcePath = $Node.SourcePath
                    DependsOn = "[SQLServerNetwork]SQLNetworking-$($instance.InstanceName)"

                }

                Log "SQLServerFirewall-$($instance.InstanceName)-Log"
                {
                    Message = "[$instance.InstanceName] - Configured firewall for: $fwFeatures"
                }

            }
            else
            {
                
                Log "SQLServerFirewall-$($instance.InstanceName)-Log"
                {
                    Message = "[$instance.InstanceName] - No features that need firewall configuration"
                }
              
            }

            $restartService = $Node.RestartRequired
            
            if($restartService)
            {
                Log "Restart-$($instance.InstanceName)-Log"
                {
                    Message = "[$instance.InstanceName] - Note: SQL Service will retstart if required"
                }
            }
            

            #Set Memory

            if($instance.DefaultMemory)
            {
                #Set Memory to default settings 
                SqlServerMemory "SQLMemory-$($instance.InstanceName)"
                {
                    Ensure = 'Absent'
                    InstanceName = $instance.InstanceName
                    DependsOn = "[SqlSetup]SQLSetup-$($instance.InstanceName)"
                }
                
                Log "Restart-$($instance.InstanceName)-Log"
                {
                    Message = "[$instance.InstanceName] - SQL Memory settings set to default"
                    DependsOn = "[SqlServerMemory]SQLMemory-$($instance.InstanceName)"
                }

            }
            else 
            {
                #Set Memory settings to custom
                #If dynamic allocation is enabled, then the max memory value needs to be null
                if($instance.DynamicAlloc)
                {
                    $instance.SQLMaxMemory = $null
                }

                SQLServerMemory "SQLMemory-$($instance.InstanceName)"
                {
                    Ensure = 'Present'
                    InstanceName = $instance.InstanceName
                    DynamicAlloc  = $instance.DynamicAlloc
                    MinMemory = $instance.MinMemory
                    MaxMemory = $instance.MaxMemory
                    DependsOn = "[SqlSetup]SQLSetup-$($instance.InstanceName)"
                }

                Log "Restart-$($instance.InstanceName)-Log"
                {
                    Message = "[$instance.InstanceName] - SQL Memory settings . Dynamic Allocation: $instance.DynamicAlloc , MinMemmory: $instance.SQLMinMemory , MaxMemory: $instance.SQLMaxMemory"
                    DependsOn = "[SqlServerMemory]SQLMemory-$($instance.InstanceName)"
                }

             

            }

            
            #SQL Secuirty Hardening - Remove built in users
            SQLServerLogin "RemoveBuiltinUsers-$($instance.InstanceName)"
            {
                ServerName  = $Node.NodeName
                InstanceName = $instance.InstanceName
                Name = 'BUILTIN\Users'
                Ensure = 'Absent'
                DependsOn = "[SqlSetup]SQLSetup-$($instance.InstanceName)"
            }
            
            
        }
    }
}


$ConfigurationData = @{
    AllNodes = @(
        @{
            #Global Varibles

            NodeName = "*"
           
            #TODO Use certificates
            PSDscAllowPlainTextPassword = $true
            PSDscAllowDomainUser =$true

            #SQL Installer Location
            SourcePath = 'C:\SQL2016'

            #Installation path for shared SQL files
            InstallSharedDir = "C:\Program Files\Microsoft SQL Server"
            #Installation path for x86 shared SQL files
            InstallSharedWOWDir = "C:\Program Files (x86)\Microsoft SQL Server"
            #Installation path for SQL instance files
            InstanceDir = "C:\Program Files\Microsoft SQL Server"

            #Sets if a restart should occure if required
            RestartService = $true
        }


       @{

            NodeName = 'TestSQL01'

            #Array of instances settings 
            Instances = @(

                            @{

                                #Instance Name 
                                #Required
                                InstanceName = 'MSSQLServer'

                                #Features to install
                                #Required
                                Features = 'SQLEngine,AS,FullText,IS'
                                
                                #Service account for the SQL service
                                #Comment out for default
                                SQLSvcAccount = Get-Credential -UserName 'TEST\SQLAdmin' -Message "SQL Engine Service Account"
                                #Service account for the SQL Agent service
                                #Comment out for default
                                AgtSvcAccount = $SQLSvcAccount
                                #Service account for Analysis Services service
                                #Comment out for default
                                #ASSvcAccount = Get-Credential -UserName 'Test\ASAdmin' -Message "SQL Integration Services Service Account"
                                #Service account for Integration Services service
                                #Comment out for default
                                #ISSvcAccount = Get-Credential -UserName 'Test\ASAdmin' -Message "SQL Analysis Services Service Account"
                                #SQL 2017 install package does not include Reporting Services
                                #Comment out for default
                                #RSServiceAccount = Get-Credential -UserName 'Test\RSAdmin' -Message "SQL Reporting Services Service Account"

                                #SQL Server Admin Accounts
                                SQLSysAdminAccounts  = 'TEST\SQLAdmin'
   
                                #SQL Analysis Services Admin Accounts
                                #Required if installing AS
                                ASSysAdminAccounts  = 'TEST\SQLAdmin'
                                 
                                #Root path for SQL database files
                                #Required if installing SQLEngine
                                InstallSQLDataDir = "C:\Program Files\Microsoft SQL Server\MSSQL14.MSSQLServer\MSSQL\Data"
                                #Path for SQL database files
                                #Required if installing SQLEngine
                                SQLUserDBDir = "C:\Program Files\Microsoft SQL Server\MSSQL14.MSSQLServer\MSSQL\Data"
                                #Path for SQL log files
                                #Required if installing SQLEngine
                                SQLUserDBLogDir = "C:\Program Files\Microsoft SQL Server\MSSQL14.MSSQLServer\MSSQL\Data"
                                #Path for SQL TempDB files
                                #Required if installing SQLEngine
                                SQLTempDBDir = "C:\Program Files\Microsoft SQL Server\MSSQL14.MSSQLServer\MSSQL\Data"
                                #Path for SQL TempDB log files
                                #Required if installing SQLEngine
                                SQLTempDBLogDir = "C:\Program Files\Microsoft SQL Server\MSSQL14.MSSQLServer\MSSQL\Data"
                                #Path for SQL backup files
                                #Required if installing SQLEngine
                                SQLBackupDir = "C:\Program Files\Microsoft SQL Server\MSSQL14.MSSQLServerWTF\MSSQL\Backup"

                                #Collation for SQL Server
                                #Required if installing SQLEngine
                                SQLCollation = 'Latin1_General_CI_AS'
                                
                                #Collation for Analysis Services
                                #Required if installing AS
                                ASCollation = "Latin1_General_CI_AS"
                                
                                #The server mode for SQL Server Analysis Services instance. Server 2017 default is TABULAR
                                #Options are: MULTIDIMENSIONAL | TABULAR | POWERPIVOT
                                #Required
                                #Required if installing SQLEngine
                                ASServerMode = 'TABULAR'

                                #Path for Analysis Services data files
                                #Required if installing AS
                                ASDataDir = 'C:\Program Files\Microsoft SQL Server\MSAS14.WTF\OLAP\Data'
                                #Path for Analysis Services log files
                                #Required if installing AS
                                ASLogDir = 'C:\Program Files\Microsoft SQL Server\MSAS14.WTF\OLAP\Log'
                                #Path for Analysis Services backup files
                                #Required if installing AS
                                ASBackupDir = 'C:\Program Files\Microsoft SQL Server\MSAS14.WTF\OLAP\Backup'
                                #Path for Analysis Services temp files
                                #Required if installing AS
                                ASTempDir = 'C:\Program Files\Microsoft SQL Server\MSAS14.WTF\OLAP\Temp'
                                #Path for Analysis Services config
                                #Required if installing AS
                                ASConfigDir = 'C:\Program Files\Microsoft SQL Server\MSAS14.WTF\OLAP\Config'

                                #Specifies whether the SQL Server instance should use a dynamic port.
                                #If set to $fasle, TcpPort is required
                                #Required
                                TcpDynamicPort = $false
                                #The TCP port(s) that SQL Server should be listening on. 
                                #To list multiplpe,list all ports separated with a comma ('1433,1600,1601')
                                #Required - if TcpDynamicPort = $false
                                TcpPort = "1433"

                                #Set if default memeory configuration should be used
                                #Required
                                DefaultMemory = $false

                                #Sets if tthe max memory will be dynamically configured.
                                #If set, MaxMemory should be set
                                #Required - if DefaultMemory = $false
                                DynamicAlloc = $false
                                #Minimum amount of memory (in MB)
                                #0 is default
                                #Required - if DefaultMemory = $false
                                MinMemory = 0
                                #Maximum amount of memory (in MB)
                                #2147483647 is default
                                #Required - if DynamicAlloc = $true
                                MaxMemory = 2147483647

                            }

                            @{

                                #Instance Name 
                                #Required
                                InstanceName = 'TestInstance2'

                                #Features to install
                                #Required
                                Features = 'SQLEngine,FullText'
                                
                                #Service account for the SQL service
                                #Comment out for default
                                #SQLSvcAccount = Get-Credential -UserName 'TEST\SQLAdmin' -Message "SQL Engine Service Account"
                                #Service account for the SQL Agent service
                                #Comment out for default
                                #AgtSvcAccount = $SQLSvcAccount
                                #Service account for Analysis Services service
                                #Comment out for default
                                #ASSvcAccount = Get-Credential -UserName 'Test\ASAdmin' -Message "SQL Integration Services Service Account"
                                #Service account for Integration Services service
                                #Comment out for default
                                #ISSvcAccount = Get-Credential -UserName 'Test\ASAdmin' -Message "SQL Analysis Services Service Account"
                                #SQL 2017 install package does not include Reporting Services
                                #Comment out for default
                                #RSServiceAccount = Get-Credential -UserName 'Test\RSAdmin' -Message "SQL Reporting Services Service Account"

                                #SQL Server Admin Accounts
                                SQLSysAdminAccounts  = 'TEST\SQLAdmin'
   
                                #SQL Analysis Services Admin Accounts
                                #Required if installing AS
                                #ASSysAdminAccounts  = 'TEST\SQLAdmin'
                                 
                                #Root path for SQL database files
                                #Required if installing SQLEngine
                                InstallSQLDataDir = "C:\Program Files\Microsoft SQL Server\MSSQL14.TestInstance2\MSSQL\Data"
                                #Path for SQL database files
                                #Required if installing SQLEngine
                                SQLUserDBDir = "C:\Program Files\Microsoft SQL Server\MSSQL14.TestInstance2\MSSQL\Data"
                                #Path for SQL log files
                                #Required if installing SQLEngine
                                SQLUserDBLogDir = "C:\Program Files\Microsoft SQL Server\MSSQL14.TestInstance2\MSSQL\Data"
                                #Path for SQL TempDB files
                                #Required if installing SQLEngine
                                SQLTempDBDir = "C:\Program Files\Microsoft SQL Server\MSSQL14.TestInstance2\MSSQL\Data"
                                #Path for SQL TempDB log files
                                #Required if installing SQLEngine
                                SQLTempDBLogDir = "C:\Program Files\Microsoft SQL Server\MSSQL14.TestInstance2\MSSQL\Data"
                                #Path for SQL backup files
                                #Required if installing SQLEngine
                                SQLBackupDir = "C:\Program Files\Microsoft SQL Server\MSSQL14.TestInstance2\MSSQL\Backup"

                                #Collation for SQL Server
                                #Required if installing SQLEngine
                                SQLCollation = 'Latin1_General_CI_AS'
                                
                                #Collation for Analysis Services
                                #Required if installing AS
                                #ASCollation = "Latin1_General_CI_AS"
                                
                                #The server mode for SQL Server Analysis Services instance. Server 2017 default is TABULAR
                                #Options are: MULTIDIMENSIONAL | TABULAR | POWERPIVOT
                                #Required if installing SQLEngine
                                #ASServerMode = 'TABULAR'

                                #Path for Analysis Services data files
                                #Required if installing AS
                                #ASDataDir = 'C:\Program Files\Microsoft SQL Server\MSAS14.WTF\OLAP\Data'
                                #Path for Analysis Services log files
                                #Required if installing AS
                                #ASLogDir = 'C:\Program Files\Microsoft SQL Server\MSAS14.WTF\OLAP\Log'
                                #Path for Analysis Services backup files
                                #Required if installing AS
                                #ASBackupDir = 'C:\Program Files\Microsoft SQL Server\MSAS14.WTF\OLAP\Backup'
                                #Path for Analysis Services temp files
                                #Required if installing AS
                                #ASTempDir = 'C:\Program Files\Microsoft SQL Server\MSAS14.WTF\OLAP\Temp'
                                #Path for Analysis Services config
                                #Required if installing AS
                                #ASConfigDir = 'C:\Program Files\Microsoft SQL Server\MSAS14.WTF\OLAP\Config'

                                #Specifies whether the SQL Server instance should use a dynamic port.
                                #If set to $fasle, TcpPort is required
                                #Required
                                TcpDynamicPort = $true
                                #The TCP port(s) that SQL Server should be listening on. 
                                #To list multiplpe,list all ports separated with a comma ('1433,1600,1601')
                                #Required - if TcpDynamicPort = $false
                                TcpPort = "1433"

                                #Set if default memeory configuration should be used
                                #Required
                                DefaultMemory = $true

                                #Sets if tthe max memory will be dynamically configured.
                                #If set, MaxMemory should be set
                                #Required - if DefaultMemory = $false
                                #DynamicAlloc = $false
                                #Minimum amount of memory (in MB)
                                #0 is default
                                #Required - if DefaultMemory = $false
                                #MinMemory = 0
                                #Maximum amount of memory (in MB)
                                #2147483647 is default
                                #Required - if DynamicAlloc = $true
                                #MaxMemory = 2147483647

                            }
                            
                        )
        }
    )
}


SQLServer2017Install -ConfigurationData $ConfigurationData -Verbose
