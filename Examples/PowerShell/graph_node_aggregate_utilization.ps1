param(
        [parameter(mandatory=$true)][string]$IP,
        [parameter(mandatory=$true)][int]$Port=8443,
        [parameter(mandatory=$true)][string]$Username
)

Function New-GoogleChart {
[CmdletBinding()]
Param (
	[Parameter(Mandatory,ValueFromPipeline)] [Object[]]$InputObject, [ValidateSet("Line","LineSoft","Bar")] [string]$ChartType = "Line",
	[Parameter(Mandatory)] [string]$XAxis,
	[Parameter(Mandatory)] [String[]]$YAxis,
	[string]$Title,
	[int]$ChartNumber = 0
)
Begin {
	Write-Verbose "$(Get-Date): New-GoogleChart function started"
	$Script = @"
	<script type="text/javascript" src="https://www.google.com/jsapi"></script>
	<script type="text/javascript">
		google.load("visualization", "1", {packages:["corechart"]});
		google.setOnLoadCallback(drawChart);
		function drawChart() {
			var grid = google.visualization.arrayToDataTable([
"@
				Switch ($ChartType) {
					"Line" {
						$CurveType = "curveType: 'none',"
						$CT = "LineChart"
						Break
					}
					"LineSoft" {
						$CurveType = "curveType: 'function',"
						$CT = "LineChart"
						Break
					}
					"Bar" {
						$CT = "BarChart"
						$CurveType = $null
						Break
					}
				}
				$ReturnObject = @()
}
    
End {
				Write-Verbose "$(Get-Date): Building jscript..."
				$Data = @( $Input )

				#Validate properties
				$Properties = $Data[0] | Get-Member -MemberType *Properties | Select -ExpandProperty Name
				If ($Properties -notcontains $XAxis) {
					Write-Warning "X-Axis: $XAxis does not exist in the property list of the object passed to the function."
					Exit
				}
				ForEach ($Property in $YAxis) {
					If ($Properties -notcontains $Property) {
						Write-Warning "Y-Axis: $Property does not exist in the property list of the object passed to the function."
						Exit
					}
				}

				$Grid = "`n            ['$($XAxis)'"
				ForEach ($Index in (0..($YAxis.Count - 1))) {
				$Grid += ", '$($YAxis[$Index])'"
				}
				$Grid += "],`n"
				ForEach ($Line in $Data) {
					$Grid += "            ['$($Line.$XAxis)'"
					ForEach ($Property in $YAxis) {
						$Grid += ", $($Line.$Property)"
					}
					$Grid += "],`n"
				}
				$Grid = $Grid.Substring(0,$Grid.Length - 2) + "`n"
				$id = "chart$($ChartNumber)_id"
$Script += @"
				$Grid
			]);

			var options$ChartNumber = {
				$CurveType
				title: '$Title',
				legend: { position: 'none' },
				vAxis: { minValue: 0, viewWindow: { min: 0 } },
			};

			var chart$ChartNumber = new google.visualization.$CT(document.getElementById('$id'));
			chart$ChartNumber.draw(grid, options$ChartNumber);
		}
	</script>
"@
		$ReturnObject += [PSCustomObject]@{
				jscript = $Script
				id = $id
		}
		Write-Verbose "$(Get-Date): New-GoogleChart function completed"
		Return $ReturnObject
}
}

Function Get-UnixDate( $UnixDate ) {
    [timezone]::CurrentTimeZone.ToLocalTime( ( [datetime]'1/1/1970').AddSeconds( $UnixDate ) )
}

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

# get the cluster
do {
	$C = invoke-restmethod -Method GET -Uri $( $URL + "/ontap/clusters" ) -Headers $Headers
	for ( $i = 1; $i -le $C.result.total_records; $i++ ) {
		write-host $( [string]$i + ": " + [string]$C.result.records[$i-1].name )
	}
	$ClusterNum = [int]( Read-Host "Select a cluster" )
	$ClusterNum--;
	if ( $ClusterNum -lt 0 -or $ClusterNum -ge $C.result.total_records ) {
		write-host $( "Error: number must be between 1 and " + [string]$C.result.total_records )
	}
} while ( $ClusterNum -lt 0 -or $ClusterNum -ge $C.result.total_records )
write-host $C.result.records[$ClusterNum].name

# get the node
do {
	$N = invoke-restmethod -Method GET -Uri $( $URL + "/ontap/nodes?cluster_key=" + $C.result.records[$ClusterNum].key ) -Headers $Headers
	for ( $i = 1; $i -le $N.result.total_records; $i++ ) {
		write-host $( [string]$i + ": " + [string]$N.result.records[$i-1].name )
	}
	$NodeNum = [int]( Read-Host "Select a node" )
	$NodeNum--;
	if ( $NodeNum -lt 0 -or $NodeNum -ge $N.result.total_records ) {
		write-host $( "Error: number must be between 1 and " + [string]$N.result.total_records )
	}
} while ( $NodeNum -lt 0 -or $NodeNum -ge $N.result.total_records )
write-host $N.result.records[$NodeNum].name

# get the aggregate
do {
	$A = invoke-restmethod -Method GET -Uri $( $URL + "/ontap/aggregates?node_key=" + $N.result.records[$NodeNum].key ) -Headers $Headers
	for ( $i = 1; $i -le $A.result.total_records; $i++ ) {
		write-host $( [string]$i + ": " + [string]$A.result.records[$i-1].name )
	}
	$AggregateNum = [int]( Read-Host "Select an aggregate" )
	$AggregateNum--;
	if ( $AggregateNum -lt 0 -or $AggregateNum -ge $A.result.total_records ) {
		write-host $( "Error: number must be between 1 and " + [string]$A.result.total_records )
	}
} while ( $AggregateNum -lt 0 -or $AggregateNum -ge $A.result.total_records )

# set the base timestamp
$TimeOrigin = New-Object -Type DateTime -ArgumentList 1970, 1, 1, 0, 0, 0, 0

# get the node utilization metrics
$NReport = @()
$AverageNodeUtilization = 0;
$NM = invoke-restmethod -Method GET -Uri $( $URL + "/ontap/nodes/" + $N.result.records[$NodeNum].key + "/metrics?name=utilization&history=true" ) -Headers $Headers
$NM.result.records.metrics.samples |% {
	$NReport += New-Object psobject -Property @{Timestamp=( $TimeOrigin.AddSeconds( $_.timestamp / 1000 ).ToString( "M/d HH:mm" ) );Value=$_.value}
	$AverageNodeUtilization += $_.value
}
$AverageNodeUtilization = $AverageNodeUtilization / $NM.result.records.metrics.samples.count

# get the aggregate utilization metrics
$AReport = @()
$AverageAggregateUtilization = 0
$AM = invoke-restmethod -Method GET -Uri $( $URL + "/ontap/aggregates/" + $A.result.records[$AggregateNum].key + "/metrics?name=utilization&history=true" ) -Headers $Headers
$AM.result.records.metrics.samples |% {
	$AReport += New-Object psobject -Property @{Timestamp=( $TimeOrigin.AddSeconds( $_.timestamp / 1000 ).ToString( "M/d HH:mm" ) );Value=$_.value}
	$AverageAggregateUtilization += $_.value
}
$AverageAggregateUtilization = $AverageAggregateUtilization / $AM.result.records.metrics.samples.count

# create the graph
$J1 = $NReport | Sort-Object Timestamp | New-GoogleChart -XAxis "Timestamp" -YAxis "Value" -Title $( "Node Utilization (Node: " + $N.result.records[$NodeNum].name + ")" ) -ChartType LineSoft -ChartNumber 1
$J2 = $AReport | Sort-Object Timestamp | New-GoogleChart -XAxis "Timestamp" -YAxis "Value" -Title $( "Aggregate Utilization (Aggregate: " + $A.result.records[$AggregateNum].name + ")" ) -ChartType LineSoft -ChartNumber 2

# create the HTML
$Header = @"
        <style>
body { background: white; }
.wrap{
    max-width:1800px;
    width:100%;
    max-height:600px;
    height:400px;
}
        </style>
        $($J1.jscript)
        $($J2.jscript)
"@
# $report | Sort-Object -Descending FreePercent | ConvertTo-Html -Head $Header -Body "<div id=""$($J.id)""></div><p><center>" | Out-File 'testchart.html' -Encoding ASCII
ConvertTo-Html -Head $Header -Body "<div class=""wrap"" id=""$($J1.id)""></div><div class=""wrap"" id=""$($J2.id)""></div><p>Average Node Utilization: $($AverageNodeUtilization)<p>Average Aggregate Utilization: $($AverageAggregateUtilization)" | Out-File 'testutilizationchart.html' -Encoding ASCII

# display the HTML
Invoke-Item 'testutilizationchart.html'
