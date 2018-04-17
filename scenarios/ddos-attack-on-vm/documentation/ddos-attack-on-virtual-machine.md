# Table of Contents
1. [Objectives](#objectives)
2. [Overview](#overview)
3. [Important Notes](#important-notes)
4. [Pre-requisites](#prerequisites)
5. [Deploy](#deployment)
6. [Perform Attack](#attack)
7. [Detect & Mitigate Attack](#detect)
8. [Teardown Deployment](#teardown)
9. [References](#references)

<a name="objectives"></a>

# Objective of the POC
Showcase DDoS protection on azure resources with public IP

<a name="overview"></a>

# Overview
It showcases following use cases
1. Perform DDoS attack on resources in a virtual network including public IP addresses associated with virtual machines by following configuration --> DDoS protection detects attack and mitigate the DDoS attack and send alert.
    * Virtual Network (VNet enabled DDoS basic protection)

<a name="important-notes"></a>

# Important Notes
Azure DDoS Protection Standard is currently in preview. Protection is provided for any Azure resource that has an Azure public IP address associated to it. such as virtual machines, load balancers, and application gateways,You need to register for the service before you can enable DDoS Protection Standard for your subscription. DDoS Protection Standard is available in the East US, East US 2, West US, West Central US, North Europe, West Europe, Japan West, Japan East, East Asia, and Southeast Asia regions only. During preview, you are not charged for using the service.

Note : To register DDoS protection service on subscription [visit this link](http://aka.ms/ddosprotection)

<a name="prerequisites"></a>

# Prerequisites
1. Azure subscription should regitered for DDoS protection.
2. Use the [private link](https://aka.ms/ddosprotectionplan) for DDoS protection feature.
3. Access to Azure subscription to deploy Virtual Machine with Virtual Network

<a name="deployment"></a>

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

8. To manually configure IIS server on VM follow below steps <br />
    a. Go to Azure Portal --> Select Resource Groups services --> Select Resource Group - "0004-ddos-attack-on-vm" <br />
    b. Select VM with name 'vm-with-ddos'


    ![](images/select-rg-and-vm.png)

    c. On Properties Page --> Click Connect to Download RDP file --> Save and Open RDP file.


    ![](images/click-on-connect.png)

    d. Enter login details (The VM login username and password is in deployment powershell output)
    
    e. Open Server Manager and install Web Server (IIS).


    ![](images/select-add-roles-and-feature.png)


    ![](images/install-iis-web-Server-on-VM.png)
               
    
9. To configure Azure Security Center, pass `<ConfigureASC>`  switch and  email address `<email id>` for notification

    `.\deploy-azuresecurityscenarios.ps1 -ConfigureASC -EmailAddressForAlerts <email id>`

10. To Create standard DDoS plan and configure with virtual network <br />

    a. Go to Azure Portal --> Click on "Create a resource" --> Search "DDoS protection plan"

      ![](images/ddos-standard-plan-1.png)
    
    b. Enter details 

      ![](images/ddos-standard-plan-2.png)

    c. Configure standard DDoS protection plan on VNet

      ![](images/select-standard-ddos-on-vnet.png)


<a name="attack"></a>

# Perform 
 ### * Attack VM without DDoS protection <br />
Microsoft Support team executed TCP SYN flood and DNS flood attack on the VM without DDoS protection. In this case DDoS attack can not be detected as shown in below images. <br />
To monitor from matrics to find public IP is under DDoS attack (Does not detect DDoS attack)  <br />
    Azure Portal-->Resource Group --> VM --> Metrics --> Select below options  <br />
    - Select specific Public IP in resource option   <br />
    - Under DDoS attack or not in metrics filter  <br />
    

   ![](images/without-ddos-protection-under-attack.png)


To monitor from matrics to find public IP inbound packets status (Does not detect DDoS attack) <br />
    Azure Portal-->Resource Group --> VM --> Metrics --> Select below options from metrics filter  <br />
    - inbound packets DDoS  <br />
    - inbound packets dropped DDoS  <br />
    - inbound packets forwarded DDoS  <br />


  ![](images/without-ddos-protection-inbound.png)

 ### * Attack on VM with DDoS protection <br />
Microsoft Support team executed TCP SYN flood and DNS flood attack on the VM without DDoS protection. In this case DDoS attack is detected as shown in below images. <br />
To monitor from matrics to find public IP is under DDoS attack (Detect DDoS attack)  <br />
    Azure Portal-->Resource Group --> VM --> Metrics --> Select below options  <br />
    - Select specific Public IP in resource option   <br />
    - Under DDoS attack or not in metrics filter  <br />
 

   ![](images/monitoring-public-IP-under-DDoS-attack.png)


To monitor from matrics to find public IP inbound packets status (Detect DDoS attack) <br />
    Azure Portal-->Resource Group --> VM --> Metrics --> Select below options from metrics filter  <br />
    - inbound packets DDoS  <br />
    - inbound packets dropped DDoS  <br />
    - inbound packets forwarded DDoS  <br />

  
   ![](images/monitoring-inbound-packets-DDoS.png)


<a name="detect"></a>

# Detect and mitigate attack
The DDoS protection detect and mitigates the attack on VM. The below image of network metrics of VM while network in attack. <br />
The DDoS protection detects and mitigates attack within 2 minitues. <br />
To monitor network in and network out follow below steps <br />
    Azure Portal-->Resource Group --> VM --> Metrics --> Select VM name in resource --> select netork in / out in metrics filter

   ![](images/monitoring-network-in-out.png)
    

The email alert configured at metrics level, This will send the alert mail if VNet is under DDoS attack over last the 5 minutes <br />
  ( Note: Deployment UserName is used to get the email alert for DDoS attack )
  
    
   ![](images/ddoS-attack-mail-alert.png)
   

<a name="teardown"></a>

## Clear Deployment 

Run following command to clear all the resources deployed during the demo.

```
.\deploy-azuresecurityscenarios.ps1 -Scenario ddos-attack-on-vm -Cleanup 
```

Verification steps -
1. Login to Azure Portal / Subscription
2. Check if all the ResourceGroup with deploymentSuffix is cleared.


<a name="references"></a>

**References** 

https://docs.microsoft.com/en-us/azure/virtual-network/ddos-protection-overview

https://azure.microsoft.com/en-in/blog/azure-ddos-protection-service-preview/

https://azure.microsoft.com/en-in/pricing/details/ddos-protection/
