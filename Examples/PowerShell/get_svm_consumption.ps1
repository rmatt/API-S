param(
        [parameter(mandatory=$false)][string]$IP,
        [parameter(mandatory=$false)][string]$Username,
        [parameter(mandatory=$false)][string]$SVM
)

Function New-GoogleChart {
[CmdletBinding()]
Param (
	[Parameter(Mandatory,ValueFromPipeline)] [Object[]]$InputObject,
	[Parameter(Mandatory)] [string]$Object,
	[Parameter(Mandatory)] [String[]]$Value,
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
				$ReturnObject = @()
}
    
End {
				Write-Verbose "$(Get-Date): Building jscript..."
				$Data = @( $Input )

				#Validate properties
				$Grid = "`n            ['$($Object)'"
				ForEach ($Index in (0..($Value.Count - 1))) {
				$Grid += ", '$($Value[$Index])'"
				}
				$Grid += "],`n"
				ForEach ($Line in $Data) {
					$Grid += "            ['$($Line.$Object)'"
					ForEach ($Property in $Value) {
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
				title: '$Title',
				height: 1200,
				is3D: true,
			};

			var chart$ChartNumber = new google.visualization.PieChart(document.getElementById('$id'));
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

if ( !$SVM ) {
	$SVM = Read-host "Enter SVM Name"
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

# get the volumes associated to the SVM in question
$S = invoke-restmethod -Method GET -Uri $( $URL + "/ontap/storage-vms?name=" + $SVM ) -Headers $Headers
$S.result.records |% {
        $V = invoke-restmethod -Method GET -Uri $( $URL + "/ontap/volumes/?storage_vm_key=" + $_.key ) -Headers $Headers
        $V.result.records |% {
		$Size = $_.size/1024/1024/1024
		$report += New-Object psobject -Property @{Volume=$_.name;Size=$Size }
        }
}

# create the graph and HTML script
$J = $report | Sort-Object Size | New-GoogleChart -Object "Volume" -Value "Size" -Title "Volume Sizes (GB) in SVM $SVM" -ChartNumber 1

# create the HTML header
$Header = @"
        <style>
        H1 {color: #000099;}
        TABLE {border-width: 1px;border-style: solid;border-color: black;border-collapse: collapse; clear:both;}
        TH {border-width: 1px;padding: 3px;border-style: solid;border-color: black;color: white;background-color: blue;font-size:1.2em;}
        TD {border-width: 1px;padding: 3px;border-style: solid;border-color: black;}
        </style>
        $($J.jscript)
"@

# create the HTML file
# $report | Sort-Object -Descending FreePercent | ConvertTo-Html -Head $Header -Body "<div id=""$($J.id)""></div><p><center>" | Out-File 'testpiechart.html' -Encoding ASCII
ConvertTo-Html -Head $Header -Body "<div id=""$($J.id)""></div><p><center>" | Out-File 'testpiechart.html' -Encoding ASCII

# display the HTML file
Invoke-Item 'testpiechart.html'
