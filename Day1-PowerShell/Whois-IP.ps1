# Pass in an IPv4 address, returns ARIN contact information about it.
# Version: 1.1 - corrected different structures used on whois :-( ... org or customer

param ($IpAddress = "66.35.45.201") # 66.35.45.201, 172.217.23.228

function Whois-IP ($IpAddress)
{
    # Build an object to populate with data, then emit it at the end.
    $poc = $IpAddress | select-object IP,Name,City,Country,Handle,RegDate,Updated
    $poc.IP = $IpAddress.Trim() 

    # Do whois lookup with ARIN on the IP address, do crude error check.
    [System.Net.WebRequest]::DefaultWebProxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials
    $webclient = New-Object System.Net.WebClient
    [xml] $ipxml = $webclient.DownloadString("http://whois.arin.net/rest/ip/$IpAddress")
    
    if (-not $?) { $poc ; return } 
    
    # Get the point of contact info for the owner organization or customer. Sometimes it differs :(
    $orguri = (($ipxml.net.customerRef.InnerText, $ipxml.net.orgRef.InnerText) -ne $null)[0]
    [xml] $orgxml = $webclient.DownloadString($orguri) # (($null, 'alpha', 1) -ne $null)[0]
    if (-not $?) { $poc ; return } 
    
    # Putting appropriate (not null) customer or org tag into orgxml
    $orgXMLnode = (($orgxml.customer, $orgxml.org) -ne $null)[0]
    
    $poc.Name = $orgXMLnode.name
    $poc.City = $orgXMLnode.city
    $poc.Country = $orgXMLnode."iso3166-1".name
    $poc.Handle = $orgXMLnode.handle

    if ($orgXMLnode.registrationDate) 
    { $poc.RegDate = $($orgXMLnode.registrationDate).Substring(0,$orgXMLnode.registrationDate.IndexOf("T")) } 

    if ($orgXMLnode.updateDate) 
    { $poc.Updated = $($orgXMLnode.updateDate).Substring(0,$orgXMLnode.updateDate.IndexOf("T")) } 

    $poc 
}

whois-ip -ipaddress $IpAddress
