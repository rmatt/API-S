param(
        [parameter(mandatory=$false)][string]$IP,
        [parameter(mandatory=$false)][string]$Username
)

# MAIN CODE
if ( !$IP ) {
        $IP = Read-Host "Enter API-S IP address"
}
$URL = $( "https://" + $IP + ":443/api/1.0" )

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

# walk the clusters, nodes and aggregates and print out free space
$C = invoke-restmethod -Method GET -Uri $( $URL + "/ontap/clusters" ) -Headers $Headers
$C.result.records |% {
	write-host $( "Cluster: " + $_.name )
	$N = invoke-restmethod -Method GET -Uri $( $URL + "/ontap/nodes?cluster_key=" + $_.key ) -Headers $Headers
	$N.result.records |% {
		write-host $( "`tNode: " + $_.name )
		$A = invoke-restmethod -Method GET -Uri $( $URL + "/ontap/aggregates?node_key=" + $_.key ) -Headers $Headers
		$A.result.records |% {
			write-host $( "`t`tAggregate: " + $_.name + ", Free Space Percent: " + (. { if ( $_.size_avail_percent ) { $_.size_avail_percent } else { 0 } } ) + "%" )
		}
				
	}
}
