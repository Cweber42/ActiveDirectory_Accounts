#                                AD Account Creation
# Author: Charles Weber
# The author offers customization and implementation services.
# Rev6 7/21/17
# Implemented Switch command to allow nesting of Gradyrs under building OU's, Created the Rename function, new users will error out and can be ignored. Email Notification to building staff of new accounts.
#Rev 6.1 10/29/19
# Updated to use latest cognosfile, changed switch to use building variables, moved filter higher in the file to avoid some errors
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
$domain = "ChangeMe.local"
#ACL domain
$domainacl = 'domain\' # This would be the first part of your username example domain\user or if your AD is ad.domain.local the user is ad\user
#Location that you want the student OU's nested under.
$stuou = "ou=students, dc=ChangeMe,dc=local"
#Student email domain
$stuemail = "ChangeMesd.com"
#Switch for Stubuildings Check in the creation ForEach Loop

#Building numbers from Eschool If you use more than the three default you will need to configure the switch commands around
# line 201 and 280
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
$stuhomedir1 = "\\ChangeMe.local\homes\Student-homes"
#$stuhomedir2 = "\\server\share\location\" #Second building or campus
#$stuhomedir3 = "\\server\share\location" #third building or campus
#You can seperate multiple buildings like this @("8","9","10") This is useful if you utilize a different specific file server per building
#Builds are LEA numbers you can find it in eschool.
$stuhomedirs1building = @("8","9,","11")
#stuhomedirs2building = @("building#") #second building or campus #
#stuhomedirs3building = @("building#") #third building or campus #

#Default New user password
#$fname.substring(0,1) + $lname.substring(0,1).ToLower() + $id.substring($id.length - 4, 4) # to create a password with firstintial, lastname then last 4 of school ID, If using the formula the password variable needs to be in the for each loop
$password = "GenericPW1"

#Generic Secufrity groups to add each student to based off the students assigned building
$elemgroup = "elemstudents" #generic security group for elementary
$msgroup = "ms-students"    #generic security group for middle school
$hsgroup = "hs-students"    #generic security group for high school

#Property to discourage duplicates from being made. Looks at the Student ID in the Cognos Report.
$propertyToCompare = 'Student ID' #AD property to filter out students, this is set to their "EmployeeID"
$newgroupspath = "OU=SSG,OU=Security Groups for GPO,DC=ChangeMe,DC=local" #OU for security groups for students

#Other variables#
$disableday = "Sunday" #Day the script will check and disable students not found in the latest cognos report
$logfiledir = "C:\scripts\active_directory\Logs\" #Location to save the logfile created by the script

#CSV import# Locations for CSV's used by the script
$csvcurrent = 'C:\scripts\Active_Directory\CurrentStu.csv' #Current students in AD
$csvreport = 'C:\scripts\Active_Directory\studentinfo.csv' #Report downloaded from Cognos/SIS
$csvnew = 'C:\scripts\Active_Directory\newstu.csv' #New students to create
$csvconsolidated = 'C:\scripts\active_directory\new1.csv' #used in function for filtering current and new students
$oucsv = 'C:\scripts\Active_Directory\nou.csv' #CSV for new OU's
$ngcsv = "C:\scripts\Active_Directory\ng.csv" #CSV for new groups by Gradyr
$csvfiltered = 'c:\scripts\active_directory\filterreport.csv'
#Email Report# Email report after the script finishes. 
$smtpserver = "smtp-relay.gmail.com" # Requires a configuration on Google admin console if you want to use google smtp. 
$mailfrom = "ad-students@ChangeMesd.com" # Can be any email that is accepted by your smtp domain
$mailto = "techcoord@ChangeMesd.com" # Email address to send the report
$mailsubject = "Student Accounts" # Timestamp will be added to the end.

#Email Notification
$bldnotification = $false
$hsbldcontact = "nope@nope"
$msbldcontact = "nope@nope"
$elembldcontact = "nope@nope"
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
& $cognosDL -report $cognosreport -savepath $cognosdir

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

#Filter Students from CSV report: Hard-coded in Rev5#
Import-Csv $csvreport | Where {$_.'grade' -ne 'PK'} | Export-Csv $csvfiltered

#Rename and Move Users to Correct OU from Cognos Report File
try {
$students = Import-Csv "$csvfiltered"  #Replace with $csvfiltered if using filter
} catch {
 Write-Host We have a problem with the CSV Report.
 exit
}

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
Switch ($Student."Current Building"){
    "$elembuild1" {$stubuildingou ='ou=elementary'}
    "$hsbuild1" {$stubuildingou ='ou=Highschool'}
    "$msbuild1" {$stubuildingou ='ou=MiddleSchool'}
    }

$checkme = Get-ADUser -Filter {(EmployeeID -eq $id) -and (UserPrincipalName -ne $principalName)} `
if($checkme){
Write-host "$id needs to be updated"
Set-ADUser -identity $checkme.ObjectGUID -GivenName $fname -Surname $lname -EmailAddress $emailadd -UserPrincipalName $principalname -SamAccountName $username -DisplayName $Fullname 
Move-ADObject -identity $checkme.ObjectGUID -TargetPath "ou=$gradyr,$stubuildingou,$stuou"
}
}

#Compare new students to Current Students#
Get-ADUser -SearchBase $stuou -Filter * -Properties EmployeeID,GivenName,Surname,EmailAddress| Select EmployeeID,GivenName,Surname,EmailAddress | Export-Csv $csvcurrent
$csv1 = Import-Csv -Path $csvfiltered  -header 'Student ID','Firstname','Lastname','Graduation Year','Grade','Gender','Current Building' #Replace with $csvfiltered if using filter
$csv2 = Import-Csv -Path $csvcurrent -header 'Student ID','Firstname','Lastname','Graduation Year','Grade','Gender','Current Building'

$duplicates = Compare-Object $csv1 $csv2 -Property $propertyToCompare -IncludeEqual -ExcludeDifferent -PassThru |
Select-Object -ExpandProperty $propertyToCompare

$csv1 |
Where-Object { $_.$propertyToCompare -notin $duplicates } |
Export-Csv -Path $csvconsolidated -notypeinformation
Get-Content $csvconsolidated| Select-object -skip 1 | %{$_-replace '"','' }|Out-file -FilePath $csvnew -force

# Configure new OU's #
$gradou = import-csv $csvreport | select -expand "Graduation Year" |Sort| GU  #Replace with $csvfiltered if using filter
$curou = Get-ADOrganizationalUnit -SearchBase $stuou -Filter * -Properties Name | Select -Expand Name

Compare-Object $gradou $curou |Where-Object {$_.Sideindicator -eq '<='} |Export-Csv $oucsv -NoTypeInformation

$ous = Import-Csv $oucsv
Foreach ($ou in $ous){
$o=$ou."InputObject"
New-ADOrganizationalUnit -Name $o -DisplayName -$o -Path $newou -ProtectedFromAccidentalDeletion $false}

#New Groups with email address# 
$gradyrs = import-csv $csvreport | select -expand "Graduation Year" |Sort| GU  #Replace with $csvfiltered if using filter
$Curgroup = Get-ADGroup -SearchBase $newgroupspath -Filter * -Properties Name
$ng = @()
Foreach($g in $Curgroup){
$ng += $g.split(' ')[0]}
Compare-Object $gradyrs $ng |Where-Object {$_.Sideindicator -eq '<='} |Export-Csv $ngcsv -NoTypeInformation

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
if(($students).count -ge 1){
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

Switch ($Student."Current Building"){
    "$elembuild1" {$stubuildingou ='ou=elementary'}
    "$hsbuild1" {$stubuildingou ='ou=Highschool'}
    "$msbuild1" {$stubuildingou ='ou=MiddleSchool'}
    }

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
-Path "ou=$gradyr,$stubuildingou,$stuou"`
-Department 'student'

If (Test-Path $homedir -PathType Container)
    {Write-host "$homedir already exists"}
    Else
    {New-Item -path $homedir -ItemType directory -Force}


$IdentityReference=$Domainacl+$username

$AccessRule=NEW-OBJECT System.Security.AccessControl.FileSystemAccessRule($IdentityReference,"FullControl",”ContainerInherit, ObjectInherit”,"None","Allow")

# Get current Access Rule from Home Folder for User
$HomeFolderACL = Get-acl -Path $homedir

$HomeFolderACL.AddAccessRule($AccessRule)

SET-ACL –path $homedir -AclObject $HomeFolderACL


If (($bldnotification) -eq $true){
#Email Building Staff New account information
  $body ="
    <p> A new account has been created for
    <p> $fullname,$id,$emailadd,$password <br>
    <p> The student will need to log onto a windows computer here at the school to set their password. Their username is also their email address. <br>
    <p> The password should be atleast 8 characters long with a capital and a number, once the student has set their password remind them to NOT SHARE it with other students or staff <br>     
    </P>"
if ($building -eq $hsbuild1){  #Edit this to match your building numbers for high school
Send-MailMessage -SmtpServer $smtpserver -From $mailfrom -To $hsbldcontact -Subject 'New student Account' -Body $body -BodyAsHtml 
} elseif ($building -eq $msbuild1){ #Edit this to match your building number for middle school
Send-MailMessage -SmtpServer $smtpserver -From $mailfrom -To $msbldcontact -Subject 'New student Account' -Body $body -BodyAsHtml 
} elseif ($building -eq $elembuild1){ #Edit this to match your building number for elementary
Send-MailMessage -SmtpServer $smtpserver -From $mailfrom -To $elembldcontact -Subject 'New student Account' -Body $body -BodyAsHtml 
}
start-sleep -Milliseconds 15
continue
}
}
}else{
Write-host "No New Students"
}

#Students OU by grad year#
try {
$students = Import-Csv "$csvfiltered"  #Replace with $csvfiltered if using filter
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
    -Members "$username" `

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
    -Members "$username" `
} elseif ($building -eq $msbuild1){ #Edit this to match your building number for middle school
add-ADGroupMember `
    -Identity "$msgroup" `
    -Members "$username" `
} elseif ($building -eq $elembuild1){ #Edit this to match your building number for elementary
add-ADGroupMember `
    -Identity "$elemgroup" `
    -Members "$username" `

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
