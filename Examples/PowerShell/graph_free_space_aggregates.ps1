param(
        [parameter(mandatory=$false)][string]$IP,
        [parameter(mandatory=$false)][string]$Username
)

Function New-GoogleChart {
[CmdletBinding()]
Param (
	[Parameter(Mandatory,ValueFromPipeline)] [Object[]]$InputObject, [ValidateSet("Line","LineSoft","Bar")] [string]$ChartType = "Line",
	[Parameter(Mandatory)] [string]$XAxis,
	[Parameter(Mandatory)] [String[]]$YAxis,
	[ValidateSet("Top","Bottom","Left","Right")] [string]$LegendLocation = "Top",
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
				legend: { position: "none" },
				chartArea:{left:'20%',top:'5%',width:'75%',height:'100%'},
				height: 800,
				bars: 'horizontal', // Required for Material Bar Charts.
				axes: { x: { 0: { side: 'top', label: 'Percentage'} } },
				bar: { groupWidth: "60%" }
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

# create the graph
$J = $report | Sort-Object -Descending FreePercent | New-GoogleChart -XAxis "Aggregate" -YAxis "FreePercent" -Title "Free Space Percentage" -LegendLocation Bottom -ChartType Bar -ChartNumber 1

# create the HTML
$Header = @"
        <style>
        H1 {color: #000099;}
        TABLE {border-width: 1px;border-style: solid;border-color: black;border-collapse: collapse; clear:both;}
        TH {border-width: 1px;padding: 3px;border-style: solid;border-color: black;color: white;background-color: blue;font-size:1.2em;}
        TD {border-width: 1px;padding: 3px;border-style: solid;border-color: black;}
        </style>
        $($J.jscript)
"@
# $report | Sort-Object -Descending FreePercent | ConvertTo-Html -Head $Header -Body "<div id=""$($J.id)""></div><p><center>" | Out-File 'testchart.html' -Encoding ASCII
ConvertTo-Html -Head $Header -Body "<div id=""$($J.id)""></div><p><center>" | Out-File 'testchart.html' -Encoding ASCII

# display the HTML
Invoke-Item 'testchart.html'
