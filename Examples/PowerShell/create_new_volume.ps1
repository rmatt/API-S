param(
        [parameter(mandatory=$true)][string]$IP,
        [parameter(mandatory=$true)][int]$Port=8443,
        [parameter(mandatory=$true)][string]$Username,
        [parameter(mandatory=$true)][string]$VolName,
        [parameter(mandatory=$true)][double]$SizeGB
)

# MAIN CODE
if ( !$IP ) {
	$IP = Read-Host "Enter API-S IP address"
}
$URL = $( "https://" + $IP + ":" + $Port + "/api/1.0" )

if ( !$Username ) {
	$Username = Read-Host "Enter username"
}

if ( !$VolName ) {
	$VolName = Read-Host "Enter new volume name"
}

if ( !$SizeGB ) {
	$SizeGB = [double]( Read-Host "Enter size (GB)" )
}

$SizeGB = $SizeGB * 1048576 * 1024

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

# get the cluster
do {
	$C = @()
	$CI = 0
	$CT = invoke-restmethod -Method GET -Uri $( $URL + "/admin/storage-systems" ) -Headers $Headers

	# parse the records to eliminate anything that isn't type = 'Ontap'
	for ( $i = 0; $i -lt $CT.result.total_records; $i++ ) {
		if ( $CT.result.records[$i].type.type -eq 'Ontap' ) {
			$C += $CT.result.records[$i]
			$CI++
		}
	}

	for ( $i = 1; $i -le $CI; $i++ ) {
		write-host $( [string]$i + ": " + [string]$C[$i-1].name )
	}
	$ClusterNum = [int]( Read-Host "Select a cluster" )
	$ClusterNum--;
	if ( $ClusterNum -lt 0 -or $ClusterNum -ge $CI ) {
		write-host $( "Error: number must be between 1 and " + [string]$CI )
	}
} while ( $ClusterNum -lt 0 -or $ClusterNum -ge $CI )
write-host $C[$ClusterNum].name

# get the SVM
do {
	$SVM = invoke-restmethod -Method GET -Uri $( $URL + "/ontap/storage-vms?cluster_key=" + $C[$ClusterNum].key ) -Headers $Headers
	for ( $i = 1; $i -le $SVM.result.total_records; $i++ ) {
		write-host $( [string]$i + ": " + [string]$SVM.result.records[$i-1].name )
	}
	$SVMNum = [int]( Read-Host "Select a node" )
	$SVMNum--;
	if ( $SVMNum -lt 0 -or $SVMNum -ge $SVM.result.total_records ) {
		write-host $( "Error: number must be between 1 and " + [string]$SVM.result.total_records )
	}
} while ( $SVMNum -lt 0 -or $SVMNum -ge $SVM.result.total_records )
write-host $SVM.result.records[$SVMNum].name

# get the aggregate
do {
	$A = invoke-restmethod -Method GET -Uri $( $URL + "/ontap/aggregates?cluster_key=" + $C[$ClusterNum].key ) -Headers $Headers
	for ( $i = 1; $i -le $A.result.total_records; $i++ ) {
		write-host $( [string]$i + ": " + [string]$A.result.records[$i-1].name )
	}
	$AggregateNum = [int]( Read-Host "Select an aggregate" )
	$AggregateNum--;
	if ( $AggregateNum -lt 0 -or $AggregateNum -ge $A.result.total_records ) {
		write-host $( "Error: number must be between 1 and " + [string]$A.result.total_records )
	}
} while ( $AggregateNum -lt 0 -or $AggregateNum -ge $A.result.total_records )

# create the body with the values for the new volume
$Body = $( "{ ""aggregate_key"": """ + $A.result.records[$AggregateNum].key + """, ""storage_vm_key"": """ +
		$SVM.result.records[$SVMNum].key +
		""", ""size"": """ + $SizeGB +
		""", ""name"": """ + $VolName + """ }" )

$NM = invoke-restmethod -Method POST -Uri $( $URL + "/ontap/volumes" ) -Headers $Headers -Body $Body -ContentType "application/json"
