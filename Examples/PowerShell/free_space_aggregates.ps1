param(
        [parameter(mandatory=$true)][string]$IP,
        [parameter(mandatory=$true)][int]$Port=8443,
        [parameter(mandatory=$true)][string]$Username
)

# MAIN CODE
if ( !$IP ) {
        $IP = Read-Host "Enter API-S IP address"
}
$URL = $( "https://" + $IP + ":" + $Port + "/api/1.0" )

if ( !$Username ) {
        $Username = Read-Host "Enter username"
}

$PW = Read-Host "Enter Password" -AsSecureString
$Password = [Runtime.InteropServices.Marshal]::PtrToStringAuto( [ Runtime.InteropServices.Marshal ]::SecureStringToBSTR( $PW ) )

$Auth = $Username + ':' + $Password
$Encoded = [System.Text.Encoding]::UTF8.GetBytes( $Auth )
$EncodedPassword = [System.Convert]::ToBase64String( $Encoded )
$Headers = @{"Authorization"="Basic $($EncodedPassword)" }

add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@

[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

# create the report
$report = @()

# walk the clusters, nodes and aggregates and print out free space
$C = invoke-restmethod -Method GET -Uri $( $URL + "/ontap/clusters" ) -Headers $Headers
$C.result.records |% {
	$CName = $_.name
	$N = invoke-restmethod -Method GET -Uri $( $URL + "/ontap/nodes?cluster_key=" + $_.key ) -Headers $Headers
	$N.result.records |% {
		$NName = $_.name
		$A = invoke-restmethod -Method GET -Uri $( $URL + "/ontap/aggregates?node_key=" + $_.key ) -Headers $Headers
		$A.result.records |% {
			$report += New-Object psobject -Property @{Cluster=$CName;Node=$NName;Aggregate=$_.name;FreePercent=(. { if ( $_.size_avail_percent ) { $_.size_avail_percent } else { 0 } } )}
		}
				
	}
}

# dump the report
$report
