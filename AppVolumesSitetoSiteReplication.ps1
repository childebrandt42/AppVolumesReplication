<#
.SYNOPSIS
    Replicate AppVolumes 4.x Applications and Packages
.DESCRIPTION
    Replicate AppVolumes 4.x Applications and Packages from Source to Destination, User Pure storage API. Required to have Pure Storage Replication setup, along with AppVolumes Storage Groups setup in Auto Selection Storage

.NOTES
    Version:          1.0.0
    Author:           Chris Hildebrandt
    Twitter:          @childebrandt42  
    Date Created:     9/5/2021
    Date Updated:     10/29/2021
#>

#---------------------------------------------------------------------------------------------#
#                                  Script Varribles                                           #
#---------------------------------------------------------------------------------------------#

# Log Location
$LogLocation = 'C:\Logs'

# Script Date Dont touch this one.
$ScriptDate = Get-Date -Format MM-dd-yyyy

$ScriptDateLog = Get-Date -Format MM-dd-yyy-HH-mm-ss

# Destination Pure Storage Array
$PureStorageArray = 'PureStorageFQDN or IP'
$PureProtectionGroupSourcev4 = 'Protection Group Name'
$TargetDataStorev4 = 'Target Datastore name'

# Destination vCenter
$vcenter = 'destination vCenter FQDN or IP'

# Datastore Name
$DataStoreNamev4 = 'Target Data Store Name'

# AppVolumes Info
$SourceServer = "Target AppVolumes Server FQDN or IP"
$TargetServer = "Source AppVolumes Server FQDN or IP"

# Script Creds Save Directory
$ScriptCredsDir = 'C:\Scripts\AppVolScript'

# Email Varibles
$EmailFrom = 'AppVolsReplicationErrors@yourserver.com'
$EmailTo = @('EmailRecipient1@yourserver.com','EmailRecipient2@yourserver.com')
$EmailServer = 'emailserver@yourserver.com'
$EmailSubject = 'AppVolumes Replication Script has run into an Issue! Fix me!'

#---------------------------------------------------------------------------------------------#
#                            Constant Script Varribles                                        #
#---------------------------------------------------------------------------------------------#

# Start Logging
Start-Transcript -Force -Path "$LogSaveLocation\ReplicationLog-$ScriptDateLog.log"

# Set Error Action
$ErrorActionPreference = "Stop"

#______________________________________________________________________________________
# Import Passwords
#______________________________________________________________________________________

#region Import Passwords

#______________________________________________________________________________________
# Check is VMware Service Account Password file exists
if(-Not (Test-Path -Path "$ScriptCredsDir\AppVolReplicationCreds.txt" ))
{
    #______________________________________________________________________________________
    # Create Secure Password File
    Get-Credential -Message "Enter Domain Account with permissions to Pure Storage Array, vCenter, And AppVolumes Servers in the format of: `"First.Last@domain.com`"" | Export-Clixml "$ScriptCredsDir\AppVolReplicationCreds.txt"
}

#______________________________________________________________________________________
# Import Secure Creds for use.
$Credentials = Import-Clixml "$ScriptCredsDir\AppVolReplicationCreds.txt"

$PureCredsUsername = $Credentials.username.Substring(0, $Credentials.username.lastIndexOf('@'))
$PureCressPassword = $Credentials.Password
$PureCreds = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $PureCredsUsername, $PureCressPassword

$RESTAPIUser = $Credentials.UserName
#$Credentials.Password | ConvertFrom-SecureString
$RESTAPIPassword = $Credentials.GetNetworkCredential().password

$AppVolRestCreds = @{
    username = $RESTAPIUser
    password = $RESTAPIPassword
}

#endregion Import Passwords

#---------------------------------------------------------------------------------------------#
#                                  Script Functions                                           #
#---------------------------------------------------------------------------------------------#

#region Script Functions

#______________________________________________________________________________________
# Start Services Function

Function Send-CustomHostError($ErrorBody) {
Write-Host "
________                                        __      __.__.__  .__   
\______ \ _____    ____    ____   ___________  /  \    /  \__|  | |  |  
 |    |  \\__  \  /    \  / ___\_/ __ \_  __ \ \   \/\/   /  |  | |  |  
 |    `   \/ __ \|   |  \/ /_/  >  ___/|  | \/  \        /|  |  |_|  |__
/_______  (____  /___|  /\___  / \___  >__|      \__/\  / |__|____/____/
        \/     \/     \//_____/      \/               \/                
__________      ___.   .__                            
\______   \ ____\_ |__ |__| ____   __________   ____  
 |       _//  _ \| __ \|  |/    \ /  ___/  _ \ /    \ 
 |    |   (  <_> ) \_\ \  |   |  \\___ (  <_> )   |  \
 |____|_  /\____/|___  /__|___|  /____  >____/|___|  /
        \/           \/        \/     \/           \/ 
" -ForegroundColor Red

# Send Mail Message due to Error
Send-MailMessage -From $EmailFrom -To $EmailTo -Subject $EmailSubject -Body $ErrorBody -SmtpServer $EmailServer -BodyAsHtml

exit 

}

#---------------------------------------------------------------------------------------------#
#                                  Script Body                                                #
#---------------------------------------------------------------------------------------------#

Try{
Disconnect-VIServer * -Force -Confirm:$false 
}Catch{}

# Connect to vCenter
Try {Connect-VIServer $vCenter -Credential $Credentials}
catch{
        # Send Error
        Send-CustomHostError "Failed to connect to vCenter $vCenter. Error $error"
}

#__________________________________________________________________________________________________________
#region Replication of v4x Stack

# Connect to PureStorage Replication LUN (V4 Disk)
Update-ReplicationLUN $PureStorageArray $PureProtectionGroupSourcev4 $TargetDataStorev4

# Rescan Storage, Mount Lun, Resignature Lun, Rename Datastore
Update-RepDataStore $DataStoreNamev4

#endregion Replication of v4x Stack

#Connect to AppVolumes Server Replicate Storage Groups, and Import AppStacks
#__________________________________________________________________________________________________________

# Connect to Source AppVolumes Server
Try{
    Invoke-RestMethod -SessionVariable SourceServerSession -Method Post -Uri "https://$SourceServer/cv_api/sessions" -Body $AppVolRestCreds 
}
catch{
    # Send Error Message
    Send-CustomHostError "Failed to connect to AppVolumes Source $SourceServer. Error $error" 
}

# Connect to Target AppVolumes Server
Try{
    Invoke-RestMethod -SessionVariable TargetServerSession -Method Post -Uri "https://$TargetServer/cv_api/sessions" -Body $AppVolRestCreds 
}
catch{
    # Send Error Message
    Send-CustomHostError "Failed to connect to AppVolumes Target $SourceServer. Error $error" 
}

# Rescan Target Appvolumes Sever Datastores.
Invoke-WebRequest -WebSession $TargetServerSession -Method post -Uri "https://$TargetServer/cv_api/datastores/rescan" -Body $AVCreds
start-sleep -Seconds 60

# Check for pending activities
Update-PendingActivities $TargetServerSession $TargetServer

# Mark 4.x LUN as unmountable
Update-AppVolStorageUnmountable $TargetServerSession $TargetServer $DataStoreNamev4

# Get Storage Groups
$StorageGroups = Invoke-RestMethod -WebSession $TargetServerSession -Method Get -Uri "https://$TargetServer/cv_api/storage_groups"

foreach($GroupID in $StorageGroups.Storage_Groups.ID){
    # Rescan Storage Group
    Invoke-RestMethod -WebSession $TargetServerSession -Method Post -Uri "https://$TargetServer/cv_api/storage_groups/$GroupID/rescan"

    # Import Apps
    Invoke-RestMethod -WebSession $TargetServerSession -Method Post -Uri "https://$TargetServer/cv_api/storage_groups/$GroupID/import"

    # Replicate Apps
    Invoke-RestMethod -WebSession $TargetServerSession -Method Post -Uri "https://$TargetServer/cv_api/storage_groups/$GroupID/replicate"

}

# Check for pending activities
Update-PendingActivities $TargetServerSession $TargetServer

# Get appstack Assignements
$SourceAssignments = (Invoke-RestMethod -WebSession $SourceServerSession -Method Get -Uri "https://$SourceServer/app_volumes/app_assignments?include=entities,filters,app_package,app_marker&").data
$TargetAssignments = (Invoke-RestMethod -WebSession $TargetServerSession -Method Get -Uri "https://$TargetServer/app_volumes/app_assignments?include=entities,filters,app_package,app_marker&").data

# Get Product Data from Source and Target
$SourceProducts = (Invoke-RestMethod -WebSession $SourceServerSession -Method get -Uri "https://$SourceServer/app_volumes/app_products").data
$TargetProducts = (Invoke-RestMethod -WebSession $TargetServerSession -Method get -Uri "https://$TargetServer/app_volumes/app_products").data

# Get Package Data from Source and Target
$SourcePackages = (Invoke-RestMethod -WebSession $SourceServerSession -Method get -Uri "https://$SourceServer/app_volumes/app_packages?include=app_markers%2Clifecycle_stage%2Cbase_app_package%2Capp_product").data
$TargetPackages = (Invoke-RestMethod -WebSession $TargetServerSession -Method get -Uri "https://$TargetServer/app_volumes/app_packages?include=app_markers%2Clifecycle_stage%2Cbase_app_package%2Capp_product").data

# Look up LifeCycle Target
$LifecycleTarget = (Invoke-RestMethod -WebSession $TargetServerSession -Method get -Uri "https://$TargetServer/app_volumes/lifecycle_stages").data
$LifecycleSource = (Invoke-RestMethod -WebSession $SourceServerSession -Method get -Uri "https://$SourceServer/app_volumes/lifecycle_stages").data

$UnassignedList = ''
$AssignedList = ''

# Add Lifecycle Data to packages

# For Each loop for each Package
foreach($TargetPackage in $TargetPackages){
    
    # Find Source Data matching GUID
    $SourceRow = $SourcePackages | Where-Object {$_.guid -eq $($TargetPackage.guid)}

    $SourceRowLifecycle =''
    $TargetRowLifecycle =''

    # Compair Lifecycle IDs
    $SourceRowLifecycle = $LifecycleSource | Where-Object {$_.id -eq $($SourceRow.lifecycle_stage_id)}
    $TargetRowLifecycle = $LifecycleTarget | Where-Object {$_.name -eq $($SourceRowLifecycle.name)}

    # Set LifeCycle Stage
    Invoke-RestMethod -WebSession $TargetServerSession -Method put -Uri "https://$TargetServer/app_volumes/app_packages/$($TargetPackage.id)?data%5Blifecycle_stage_id%5D=$($TargetRowLifecycle.id)"

    # Check if Current on source if so set on Target
    if($SourceRow.app_markers.name -eq "CURRENT"){
        # Set App Status Marker (AKA Set current)
        Invoke-RestMethod -WebSession $TargetServerSession -Method put -Uri "https://$TargetServer/app_volumes/app_products/$($TargetPackage.app_product_id)/app_markers/CURRENT?data%5Bapp_package_id%5D=$($TargetPackage.id)"
    }
}


# Unassign all Assignments not in source 
foreach($TargetAssignment in $TargetAssignments){
    
    #$TargetNotMatch = ""

    $TargetMatch = $SourceAssignments | Where-Object {($_.app_product_name -like $($TargetAssignment.app_product_name)) -and ($_.entities.distinguished_name -like $($TargetAssignment.entities.distinguished_name))}

    if([string]::IsNullOrWhiteSpace($TargetMatch)){
        
        Write-Host "Unassigning app $($TargetAssignment.app_product_name) for user or group $($TargetAssignment.entities.name) from AppVolumes Server $TargetServer"
        
        Try{
            Invoke-RestMethod  -WebSession $TargetServerSession -Method Post -Uri "https://$TargetServer/app_volumes/app_assignments/delete_batch?ids%5B%5D=$($TargetAssignment.id)" | Out-Null
        }
        Catch {
            Write-Host "Failed to Unassign $($TargetAssignment.app_product_name) for user or group $($TargetAssignment.entities.name) from AppVolumes Server $TargetServer"
        }

        # Build Array for Change Update
        $UnassignedList += "Unassigning app $($TargetAssignment.app_product_name) for user or group $($TargetAssignment.entities.name) from AppVolumes Server $TargetServer" | Out-String
    }    
}

Write-host "About to Start Source Assigments" 

Foreach($SourceAssignment in $SourceAssignments){
    
    $SourceMatchTarget = ''
    $SourceMatchTarget = $TargetAssignments | Where-Object {(($_.app_product_name -like $($SourceAssignment.app_product_name)) -and ($_.entities.distinguished_name -like $($SourceAssignment.entities.distinguished_name)))}

    if($SourceAssignment.app_product_name -notlike $SourceMatchTarget.app_product_name){

        $TargetRow = ''
        $SourceRow = ''
        $TargetRow = $TargetProducts | Where-Object {$_.name -like $($SourceAssignment.app_product_name)}
        $SourceRow = $SourceProducts | Where-Object {$_.name -eq $($SourceAssignment.app_product_name)}

        if(!([string]::IsNullOrWhiteSpace($TargetRow))){
        
            Foreach($SourceEntitie in $SourceAssignment.entities){
            
                $AssignUserOrGroup = $($SourceEntitie.distinguished_name)

                # Add extra \ after CN=Lastname
                if($AssignUserOrGroup -notcontains '\\' -and $($SourceEntitie.entity_type) -eq 'User'){
                    $AssignUserOrGroup = $AssignUserOrGroup.Insert($AssignUserOrGroup.IndexOf('\'),'\')
                }

                $AssignmentJsonBody = ''
                # Build Json Body
                $AssignmentJsonBody = "{""data"":[{""app_product_id"":$($TargetRow.id),""entities"":[{""path"":""$AssignUserOrGroup"",""entity_type"":""$($SourceEntitie.entity_type)""}],""app_package_id"":null,""app_marker_id"":$(($TargetPackages | Where-Object {$_.id -eq $($TargetRow.app_packages.id)}).app_markers.id)}]}"

                Write-Host "Assigning App $($TargetRow.name) to User or Group $($SourceEntitie.account_name) to AppVolumes Server $TargetServer"
        
                # Build Array for Change Update
                $AssignedList += "Assigning App $($TargetRow.name) to User or Group $($SourceEntitie.account_name) to AppVolumes Server $TargetServer" | Out-String
        
                Try{
                    # Assign User or Group
                    Invoke-RestMethod  -WebSession $TargetServerSession -Method Post -Uri "https://$TargetServer/app_volumes/app_assignments" -Body $AssignmentJsonBody -ContentType 'application/json' | Out-Null

                }
                Catch
                {
                    #Send-CustomHostError "Failed to Assign $($TargetAssignment.app_product_name) for user or group $($TargetAssignment.entities.name) to AppVolumes Server $TargetServer"
                    Write-host "Failed to Assign $($SourceEntitie.name) for user or group $($SourceEntitie.upn) to AppVolumes Server $TargetServer" -ForegroundColor Red
                }        
            }
        }
    }
}

# Wait for Pending Activities to finish
Update-PendingActivities $TargetServerSession $TargetServer

# Detach Replication LUNs
$ESXiHosts = Get-vmhost
foreach($ESXiHost in $ESXiHosts){
    Try{
    Remove-Datastore -VMhost $ESXiHost -datastore $DataStoreNamev4 -Confirm:$false  
    } Catch{}
}

# Disconnect from vCenter
Disconnect-VIServer -Server $vcenter -Confirm:$false  
write-host "Disconnected from $Vcenter"  

# End the Log gathering
Try{
Stop-Transcript | out-null -ErrorAction SilentlyContinue
} Catch{}