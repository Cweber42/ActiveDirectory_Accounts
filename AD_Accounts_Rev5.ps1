﻿#                                AD Account Creation
# Author: Charles Weber
# Date: 3/23/15
# Rev1 7/14/15 Added the Remove specials to reduce errors and complications with special characters in names and other services
# Rev2 8/16/15 Added the add to groups and generic security groups
# Rev3 5/9/16 Created functions to filter out current students, generate a report of new students. 
# Changed usernames to be firstname.lastnamegradyr example charlie.weber16
# Rev4 6/6/16 Added auto creation of Groups and OU's based on student Gradyrs if they do not exist
# Rev5 Rewrite of variables for easier configuration. Changed ID from Office to EmployeeID, the student ID is considered PII

#################
# Special THanks#
#################
#Craig Milsap-Gentry Public schools
#Miles Eubanks-Praire Grove Public Schools
#John Sullivan- Searcy Public Schools

###############
# Instructions#
###############
# You will need to edit the variables for your environment
# You will need to go through the script and edit the areas marked for it to work correctly in your environment
# The report used in this script can be found on Cognos The location of the file is Student Management System > Demographics > Demographic Download Files,
# and name of the file is APSCN Student General Information File. Copy this to your Cognos folder and name it.
# You will need the Cognos powershell download script and report.

#Example Usernames#
#Default for the script is Firstname.Lastnamelast2ofgradyr

#Firstname + "."+ Lastname
#Charlie.Weber

#Firstname + "."+ Lastname +Gradyr
#Charlie.Weber2015
#or
#Firstname + "."+ Lastname +Gradyr.Substring(2) <-This is default setting
#Charlie.Weber15

#Firstname.substring(0,1) + "." + Lastname
#c.weber

#Firstname.substring(0,1) + "." + Lastname + Gradyr.Substring(2)
#c.weber15

#Script does have the OPTION to move disabled accounts. If you use this with GADS, I recommend configuring GADS to suspend your users and not delete

### Variables to Edit ###

#Cognos Variables#
#Location of the powershell script to run Cognos download. Can work with UNC \\server\share\ if the account has R/W access
$cognosDL =  "C:\Scripts\CognosDownload.ps1"
#Name of the report in Cognos to download
$cognosreport = "studentinfo"
#File location to save the Report. Can work with UNC \\server\share\ if the account has R/W access
$cognosdir = "c:\scripts\active_directory"

#Active Directory Variables#
#Your local domain, this is what you see at the root of your AD computers/users console.
$domain = "domainchangeme.local"
#Location that you want the student OU's nested under.
$stuou = "ou=students, dc=domainchangeme,dc=local"
#Student email domain
$stuemail = "domainchange.com"

#Building numbers from Eschool
$elembuild1 = "8"
#$elembuild2
#$elembuild3
$msbuild1 = "11"
#$msbuild2
#$msbuild3
$hsbuild1 = "9"
#$hsbuild2
#$hsbuild3

#Student home directories. They map accord to the dirsbuilding. 
#I am using DFS so all my directories reside under \\domain.local\share\share
$stuhomedir1 = "\\domainchangeme.local\homes\Student-homes"
#$stuhomedir2 = "\\server\share\location\" #Second building or campus
#$stuhomedir3 = "\\server\share\location" #third building or campus
#You can seperate multiple buildings like this @("8","9","10") This is useful if you utilize a different specific file server per building
#Builds are LEA numbers you can find it in eschool.
$stuhomedirs1building = @("8","9,","11")
#stuhomedirs2building = @("building#") #second building or campus #
#stuhomedirs3building = @("building#") #third building or campus #

#Default New user password
#$fname.substring(0,1) + $lname.substring(0,1).ToLower() + $id.substring($id.length - 4, 4) to create a password with firstintial, lastname then last 4 of school ID
$password = "Bulldogs1"

#Generic Secufrity groups to add each student to based off the students assigned building
$elemgroup = "elemstudents" #generic security group for elementary
$msgroup = "ms-students"    #generic security group for middle school
$hsgroup = "hs-students"    #generic security group for high school

#Property to discourage duplicates from being made. Looks at the Student ID in the Cognos Report.
$propertyToCompare = 'Student ID' #AD property to filter out students, this is set to their "EmployeeID"
$newgroupspath = "OU=SSG,OU=Security Groups for GPO,DC=domainchangeme,DC=local" #OU for security groups for students

#Other variables#
$disableday = "Sunday" #Day the script will check and disable students not found in the latest cognos report
$logfiledir = "C:\scripts\active_directory\Logs\" #Location to save the logfile created by the script
#Properties to Compare variable#
$propertiestocompare = 'EmployeeID,GivenName,Surname,EmailAddress'

#CSV import# Locations for CSV's used by the script
$csvcurrent = 'C:\scripts\Active_Directory\CurrentStu.csv' #Current students in AD
$csvreport = 'C:\scripts\Active_Directory\studentinfo.csv' #Report downloaded from Cognos/SIS
$csvnew = 'C:\scripts\Active_Directory\newstu.csv' #New students to create
$csvconsolidated = 'C:\scripts\active_directory\new1.csv' #used in function for filtering current and new students
$oucsv = 'C:\scripts\Active_Directory\nou.csv' #CSV for new OU's
$ngcsv = "C:\scripts\Active_Directory\ng.csv" #CSV for new groups by Gradyr

#Email Report# Email report after the script finishes. 
$smtpserver = "smtp-relay.gmail.com" # Requires a configuration on Google admin console if you want to use google smtp. 
$mailfrom = "ad-students@domainchangemesdsd.com" # Can be any email that is accepted by your smtp domain
$mailto = "techcoord@domainchangemesd.com" # Email address to send the report
$mailsubject = "Student Accounts" # Timestamp will be added to the end.

#############
# Functions #
#############

function RemoveSpecials ([String]$in)
{
 $in = $in -replace("\(","") #Remove ('s
 $in = $in -replace("\)","") #Remove )'s
 $in = $in -replace("\.","") #Remove Periods
 $in = $in -replace("\'","") #Remove Apostrophies
 return $in
}

#Script# It is strongly encouraged you do not edit below this line

#Start transcript and download Cognos Report#
$logfile = "$logfiledir\$(get-date -f yyy-MM-dd-HH-mm-ss).log"
Try {Start-Transcript ($logfile)} catch {Stop-Transcript; Start-Transcript ($logfile)}
do{
    & $cognosDL $cognosreport $cognosdir
    if ($lastexitcode -ne 0){
    Write-host "Failed to download Cognos Report"
        $numtries++
            if($numtries -gt 3) {exit}
        Start-Sleep -Seconds 5
        } else {
            $success = $true
            }
} while (!$success);

#load AD module#
If (Get-Module -ListAvailable | Where-Object{$_.Name -eq "ActiveDirectory"}){
Import-Module ActiveDirectory
} else {
Write-host "ActiveDirectory Module not available"
exit
}

#Disable Student accounts on $disableday#
 if ((get-date).dayofweek -eq $disableday) {
	write-host "Disabling all student accounts." -ForegroundColor Red
	Get-ADUser -Filter * -Properties division -SearchBase $stuou | Set-ADUser -Enabled:$false
}

#Compare new students to Current Students#
Get-ADUser -SearchBase $stuou -Filter * -Properties EmployeeID,GivenName,Surname,EmailAddress| Select EmployeeID,GivenName,Surname,EmailAddress | Export-Csv $csvcurrent
$csv1 = Import-Csv -Path $csvreport  -header 'Student ID','Firstname','Lastname','Graduation Year','Grade','Gender','Current Building'
$csv2 = Import-Csv -Path $csvcurrent -header 'Student ID','Firstname','Lastname','Graduation Year','Grade','Gender','Current Building'

$duplicates = Compare-Object $csv1 $csv2 -Property $propertyToCompare -IncludeEqual -ExcludeDifferent -PassThru |
Select-Object -ExpandProperty $propertyToCompare

$csv1 |
Where-Object { $_.$propertyToCompare -notin $duplicates } |
Export-Csv -Path $csvconsolidated
Get-Content $csvconsolidated | %{$_-replace '"','' }|Out-file -FilePath $csvnew -force

# Configure new OU's #
$gradou = import-csv $csvreport | select -expand "Graduation Year" |Sort| GU
$curou = Get-ADOrganizationalUnit -SearchBase $stuou -Filter * -Properties Name | Select -Expand Name

Compare-Object $gradou $curou |Where-Object {$_.Sideindicator -eq '<='} |Export-Csv $oucsv -NoTypeInformation

$ous = Import-Csv $oucsv
Foreach ($ou in $ous){
$o=$ou."InputObject"
New-ADOrganizationalUnit -Name $o -DisplayName -$o -Path $newou -ProtectedFromAccidentalDeletion $false}

#New Groups with email address#
$gradyrs = import-csv $csvreport | select -expand "Graduation Year" |Sort| GU
$Curgroup = Get-ADGroup -SearchBase $newgroupspath -Filter * -Properties Name | Select -Expand Name
Compare-Object $gradyrs $Curgroup |Where-Object {$_.Sideindicator -eq '<='} |Export-Csv $ngcsv -NoTypeInformation

$groups = Import-Csv $ngcsv

Foreach ($group in $groups){
$g=$group."InputObject"

New-ADGroup -Name $g -SAMaccountName $g -GroupCategory Security -GroupScope Global -Path $newgroupspath -Description "Security group for students in $g Graduation Year" -otherattributes @{'mail' ="$g@$stuemail"}}

#Cleanup Generic Groups#
if ((get-date).DayOfWeek -eq $disableday){
Get-ADGroupMember "$msgroup" | ForEach-Object {Remove-ADGroupMember "$msgroup" $_ -Confirm:$false}
Get-ADGroupMember "$hsgroup" | ForEach-Object {Remove-ADGroupMember "$hsgroup" $_ -Confirm:$false}
Get-ADGroupMember "$elemgroup" | ForEach-Object {Remove-ADGroupMember "$elemgroup" $_ -Confirm:$false}
}

#Import CSV for new students#
try {
$students= Import-Csv $csvnew
} catch {
 Write-Host "We have a problem with the CSV file."
 exit
}

#Create new AD accounts#
write-host "Creating Student Accounts"
foreach ($student in $students){
$fname = (RemoveSpecials($student.Firstname))
$lname = (RemoveSpecials($student.Lastname)) 
$Fullname = $fname + " " + $lname
$gradyr = $student."Graduation Year"
$id = $student."Student ID" 
$username = $fname + "." + $lname + $gradyr.substring(2)
if ($username.length -gt 20) { $username = $username.substring(0,20) } #shorten username to 20 characters for sAMAccountName
$emailadd = $fname+"."+$lname+ $gradyr.substring(2) + "@" + $stuemail
$principalname = $fname+"."+$lname+ $gradyr.substring(2) + "@" + $stuemail
$homedir = $stuhomedir1 + "\" + $gradyr+ "\"+ $username
$building = $student."Current Building" #Edit this to match your CSV If your header is not exactly Current Building

Write-host $Fullanme $username $password $building
	#create the new user with long samaccountname
	Write-Host `nCreating new user: $username in $gradyr
New-Aduser `
-sAMAccountName $username `
-givenName $fname `
-Surname $lname `
-UserPrincipalName $principalname `
-DisplayName $fullname `
-name $fullname -homeDrive "h:" `
-homeDirectory $homedir `
-scriptPath "logon.bat" `
-EmailAddress $emailadd `
-EmployeeID	 $id `
-ChangePasswordAtLogon $true `
-AccountPassword (ConvertTo-SecureString "$password" -AsPlainText -force) `
-Enabled $true `
-Path "ou=$gradyr,$stuou"`
-Department 'student'
start-sleep -Milliseconds 15
continue
}

try {
$students = Import-Csv "$csvreport"
} catch {
 Write-Host We have a problem with the CSV Report.
 exit
}


Foreach ($student in $students){
$fname = (RemoveSpecials($student.Firstname)) #Edit this to match your CSV if your header is not exactly Firstname
$lname = (RemoveSpecials($student.Lastname)) #Edit this to match your CSV if your header is not exactly Lastname
$gradyr = $student."Graduation Year" #Edit this to match your CSV if your header is not exactly Graduation Year
$username = $fname + "." + $lname + $gradyr.substring(2)
if ($username.length -gt 20) { $username = $username.substring(0,20) } #shorten username to 20 characters for sAMAccountName
add-ADGroupMember `
    -Identity "$gradyr" `
    -Member "$username" `

Write-Host $username added to $gradyr
start-sleep -Milliseconds 15
}


#Students OU by grad year#
try {
$students = Import-Csv "$csvreport"
} catch {
 Write-Host "We have a problem with the CSV Report."
 exit
}


Foreach ($student in $students){
$fname = (RemoveSpecials($student.Firstname)) #Edit this to match your CSV if your header is not exactly Firstname
$lname = (RemoveSpecials($student.Lastname)) #Edit this to match your CSV if your header is not exactly Lastname
$gradyr = $student."Graduation Year" #Edit this to match your CSV if your header is not exactly Graduation Year
$username = $fname + "." + $lname + $gradyr.substring(2)
if ($username.length -gt 20) { $username = $username.substring(0,20) } #shorten username to 20 characters for sAMAccountName
add-ADGroupMember `
    -Identity "$gradyr" `
    -Member "$username" `

Write-Host $username added to $gradyr
start-sleep -Milliseconds 15
}

#Students by building#

Foreach ($student in $students){
$fname = (RemoveSpecials($student.Firstname)) #Edit this to match your CSV if your header is not exactly Firstname
$lname = (RemoveSpecials($student.Lastname)) #Edit this to match your CSV if your header is not exactly Lastname
$gradyr = $student."Graduation Year" #Edit this to match your CSV if your header is not exactly Graduation Year
$username = $fname + "." + $lname + $gradyr.substring(2)
if ($username.length -gt 20) { $username = $username.substring(0,20) } #shorten username to 20 characters for sAMAccountName
$building = $student."Current Building" #Edit this to match your CSV If your header is not exactly Current Building
if ($building -eq $hsbuild1){  #Edit this to match your building numbers for high school
add-ADGroupMember `
    -Identity "$hsgroup" `
    -Member "$username" `
} elseif ($building -eq $msbuild1){ #Edit this to match your building number for middle school
add-ADGroupMember `
    -Identity "$msgroup" `
    -Member "$username" `
} elseif ($building -eq $elembuild1){ #Edit this to match your building number for elementary
add-ADGroupMember `
    -Identity "$elemgroup" `
    -Member "$username" `

start-sleep -Milliseconds 15
}
}

#Enable Student Accounts#
write-host "Enabling all student accounts." -ForegroundColor Yellow
 Foreach ($student in $students){
 $fname = (RemoveSpecials($student.Firstname)) 
$lname = (RemoveSpecials($student.Lastname)) 
$gradyr = $student."Graduation Year" 
$username = $fname + "." + $lname + $gradyr.substring(2)
if ($username.length -gt 20) { $username = $username.substring(0,20) } 
		Get-ADUser -Identity $username | Set-ADUser -Enabled:$true
Write-host $username "enabled"
}

Stop-Transcript


#Email you a report#
$msg = New-Object Net.Mail.MailMessage
$smtp = New-Object Net.Mail.SmtpClient($smtpserver)
$msg.From = $mailfrom
$msg.To.Add($mailto)
$msg.subject = "$mailsubject - $(Get-Date)"
$logcontents = Get-Content $logfile 
$msg.Body = $($logcontents[5..($logcontents.length - 4)] | Out-String)
$smtp.send($msg)

# To move the users 
#Search-ADAccount –AccountDisabled –UsersOnly –SearchBase “OU=Employees,DC=domain,DC=local”  | 
#Move-ADObject –TargetPath “OU=employee,ou=Disabled Accounts, DC=domain,DC=local”

#Search-ADAccount –AccountDisabled –UsersOnly –SearchBase “OU=students,DC=domain,DC=local”  | 
#Move-ADObject –TargetPath “OU=students,ou=Disabled Accounts, DC=domain,DC=local”