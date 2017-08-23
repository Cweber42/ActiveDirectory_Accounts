# ActiveDirectory_Accounts
Automation for Active Directory from Eschool/Cognos
I can be contacted Here:
https://goo.gl/forms/x27wHLgfIqTANefv2 [Google Form] for customization and implementation pricing.


The primary job of the script is AD account creation and management:
1) Create Security groups by grad year
2) Create OU's and Nest them under building # (as a common name like MS/HS etc)
3) Create the user accounts
4) Place all users in generic building and gradyr groups
5) Disable students who have left the district on Sundays
6) Rename students and update the information for SAM/UPN/Email/Displaynames from the cognos CSV
7) Added the email notification to specified people in each building, each account that is created generates an individual email with the students Name, Student ID, email address and password,
8) Creates the home dir and sets the ACLs, the created directory inherits from the parent directory and then gives FullControl access to the student account.

# Date: 3/23/15
# Rev1 7/14/15 
 Added the Remove specials to reduce errors and complications with special characters in names and other services
# Rev2 8/16/15 
 Added the add to groups and generic security groups
# Rev3 5/9/16 
 Created functions to filter out current students, generate a report of new students. 
 Changed usernames to be firstname.lastnamegradyr example charlie.weber16
# Rev4 6/6/16 
 Added auto creation of Groups and OU's based on student Gradyrs if they do not exist
# Rev5 
 Rewrite of variables for easier configuration. Changed ID from Office to EmployeeID, the student ID is considered PII
# Rev6 8/2/17
 Implemented Switch command to allow nesting of Gradyrs under building OU's, Created the Rename function, 
 new users will error out and can be ignored. Email Notification to building staff of new accounts. 
 Create home directories and set ACL for the useraccount and inherit the file share properties. 
