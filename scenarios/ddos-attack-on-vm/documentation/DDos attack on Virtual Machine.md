# Objective of the POC
Showcase DDoS protection on azure resources with public IP

# Overview
It showcases following use cases
1. Perform DDoS attack on resources in a virtual network including public IP addresses associated with virtual machines by following configuration --> DDoS protection detects attack and mitigate the DDoS attack and send alert.
    * Virtual Network (VNet enabled DDoS basic protection)

# Important Notes
Azure DDoS Protection Standard is currently in preview. Protection is provided for any Azure resource that has an Azure public IP address associated to it, such as virtual machines, load balancers, and application gateways,You need to register for the service before you can enable DDoS Protection Standard for your subscription. DDoS Protection Standard is available in the East US, East US 2, West US, West Central US, North Europe, West Europe, Japan West, Japan East, East Asia, and Southeast Asia regions only. During preview, you are not charged for using the service.

# Prerequisites
1. Azure subscription should regitered for DDoS protection.
2. Use the [private link](https://aka.ms/ddosprotectionplan) to use DDoS protection feature.
3. Access to Azure subscription to deploy Virtual Machine with Virtual Network

# Deploy

1. Go to Edge Browser and Open [Azure Cloud Shell](https://shell.azure.com/)
1. Change directory to CloudDrive directory 

    `cd $Home\CloudDrive `

1. Clone Azure-Security-Scenarios repos to CloudDrive.

    `git clone https://github.com/AvyanConsultingCorp/azure-security-scenarios.git`

1. Change directory to azure-security-scenarios
 
    `cd .\azure-security-scenarios\`

1. Run below to get list of supported scenarios

    `.\deploy-azuresecurityscenarios.ps1 -Help`

1. If you are using Cloud Shell you can simply pass 2 parameters to run the deployment. Deployment takes  40-45 mins to complete.

    `.\deploy-azuresecurityscenarios.ps1 -Scenario "ddos-attack-on-vm" -Command Deploy  -Verbose`

1. However, if you are running on a local machine pass additional parameters to connect to subscription and run the deployment. Deployment takes  40-45 mins to complete.

    `.\deploy-azuresecurityscenarios.ps1 -SubscriptionId <subscriptionId> -UserName <username> -Password <securePassword> -Scenario "ddos-attack-on-vm" -Command Deploy   -Verbose`

8. To manually configure IIS server on VM follow below steps
    a. Go to Azure Portal --> Select Resource Groups services --> Select Resource Group - "0004-ddos-attack-on-vm"
    b. Select VM with name 'vm-with-ddos'
        ![](images/Select-RG-and-VM.png)
    c. On Properties Page --> Click Connect to Download RDP file --> Save and Open RDP file. 
        ![](images/Click-on-connect.png)
    d. Enter loginid=vmadmin and pwd=GY45s@67hx!K
    e. Open Server Manager and install Web Server (IIS).
    ![](images/Select-Add-roles-and-feature.png)
    ![](images/Install-IIS-Web-Server-on-VM.png)
    
    
8. To configure Azure Security Center, pass `<ConfigureASC>`  switch and  email address `<email id>` for notification

    `.\deploy-azuresecurityscenarios.ps1 -ConfigureASC -EmailAddressForAlerts <email id>`
    
8. Link Azure Security Center to OMS manually as shown in below screen shot


    Azure Portal  - Security Center - Security policy - Select Subscription - Security policy - Data Collection

    
    ![](images/sql-inj-asc-oms.png)
    

# Attack on VM without DDoS protection 


# Attack on VM with DDoS protection 

# Use case - 1
Attack on web app with
* Application gateway - WAF - Detection mode 
* SQL server and database with Threat Detection disabled. 

1. Go to Azure Portal --> Select Resource Groups services --> Select Resource Group - <prefix> "-sql-injection-attack-on-webapp"

2. Select Application Gateway with name 'appgw-detection-' as prefix.

    ![](images/sql-inj-appgateway-det-location.png)

3. Application Gateway WAF enabled and Firewall in Detection mode as shown below.

    ![](images/sql-inj-appgateway-waf-det.png)

4. On Overview Page --> Copy Frontend public IP address (DNS label) as
    ![](images/sql-inj-appgateway-det-ip.png)

5. Open Internet Explorer with above details as shown below  
    ![](images/sql-inj-webapp-contoso-landingpage.png)

6. Click on Patient link it will display list of details 

    ![](images/sql-inj-webapp-contoso-patients-defpage.png)

7. Perform SQL Injection attack by copying " **'order by SSN--** " in search box and click on "Search". Application will show sorted data based on SSN.

    ![](images/sql-inj-webapp-contoso-patients-attack-page.png)    
    
    
# Detect
###  Detection using OMS
To detect the attack execute following query in Azure Log Analytics
1. Go to Azure Portal --> navigate to resource group 'azuresecuritypoc-common-resources'  

![](images/sql-inj-common-oms-location.png) 

2. Go to Log analytics --> Click on Log Search --> Type query search 

    ```AzureDiagnostics | where Message  contains "Injection" and action_s contains "detected"```

    ![](images/sql-inj-oms-log-ana-location.png) 
    
3. Following details gets logged 

    ![](images/sql-inj-log-analytics-det.png) 
    
 ###  Azure Security Center Recommendation
 
1. Azure Security Center gives  recommendations to enable Auditing and Threat Detection and allows you to perform  steps from the console itself.

![](images/sql-inj-asc-recom.png) 

2. Azure Portal > Security Center - Overview > Data Resources > contosoclinic > Enable Auditing & Threat detection on SQL databases >Auditing & Threat Detection 

![](images/sql-inj-db-td-enabled.png)

## Use case - 2

Once Auditing & Threat Detection is database is enabled for SQL database, Azure Security Center sends email alert mentioned in Send alert to field. Execute the step 7 to perform SQL Injection attack

![](images/sql-inj-detection-mail.png)


# Prevention

  * Update Web application firewall mode to Prevention for application gateway. This will take 5-10 mins. Hence we will connect the application using Application Gateway (WAF- Prevention mode) 

    ![](images/sql-inj-appgateway-waf-prev.png)    
    
  

## Prevention Detection (Use case - 3)

* Execute the step 7 to perform SQL Injection attack, Application Gateway will prevent access

    ![](images/403-forbidden-access-denied.png)  

 
* To detect the prevention of attack execute following query in Azure Log Analytics


    ```AzureDiagnostics | where Message  contains "injection" and action_s contains "blocked"```
    
    ![](images/sql-inj-log-analytics-blocked.png)  


    You will notice events related to detection and prevention items. First time it takes few hours for OMS to pull logs for detection and prevention events. For subsequent requests it takes 10-15 mins to reflect in OMS, so if you don't get any search results, please try again after sometime.
    
## Clear Deployment 

Run following command to clear all the resources deployed during the demo.

```
.\deploy-azuresecurityscenarios.ps1 -Scenario sql-injection-attack-on-webapp -Cleanup 
```

Verification steps -
1. Login to Azure Portal / Subscription
2. Check if all the ResourceGroup with deploymentSuffix is cleared.




**References** 

https://docs.microsoft.com/en-us/azure/application-gateway/application-gateway-introduction
 
https://docs.microsoft.com/en-us/azure/application-gateway/application-gateway-web-application-firewall-overview
 
https://docs.microsoft.com/en-us/azure/sql-database/
