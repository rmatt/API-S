#!/usr/bin/python


import getpass
import warnings
import requests
import json

html_prefix = '''<html>
  <head>
    <script type="text/javascript" src="https://www.gstatic.com/charts/loader.js"></script>
    <script type="text/javascript">
      google.charts.load('current', {'packages':['corechart']});
      google.charts.setOnLoadCallback(drawChart);
      function drawChart() {

        var data = google.visualization.arrayToDataTable([
          ['aggr name', 'Size avail'],'''
          
html_suffix = '''        ]);

        var options = {
          title: 'My Daily Activities'
        };

        var chart = new google.visualization.BarChart(document.getElementById('piechart'));

        chart.draw(data, options);
      }
    </script>
  </head>
  <body>
    <div id="piechart" style="width: 900px; height: 500px;"></div>
  </body>
</html>'''


warnings.filterwarnings('ignore', 'Unverified HTTPS request')

url = raw_input("Enter the base URL (e.g. https://10.0.0.227:8443/api/1.0/ontap): ")
user = raw_input('Enter admin user name: ')
password = getpass.getpass('Enter password: ')
html_file_name = raw_input('Enter the path to the graph file(e.g. /Users/turie/Sites/google-graph.html): ')

clusters_json = requests.get(url + '/clusters', auth=(user,password), verify=False)
clusters = json.loads(clusters_json.text)
if clusters['status']['code'] != 'SUCCESS':
   print "Failed to communicate with the API - S server"
   exit(1)
elif clusters['result']['total_records'] == 0:
   print "No clusters found to query"
   exit(0)

cluster_selected = False
while not cluster_selected:
   for cluster_num in range( 0, int(clusters['result']['total_records']) ):
      print str(cluster_num) + ': ' + clusters['result']['records'][cluster_num]['name']
   cluster_entered = raw_input("Enter the desired cluster number: ")
   if int(cluster_entered) < 0 or int(cluster_entered) > int(clusters['result']['total_records']):
      print "ERROR: Cluster number selected must be within valid range"
   else:
      cluster_selected = True

cluster_key = clusters['result']['records'][cluster_num]['key']

aggrs_json = requests.get(url + '/aggregates?cluster_key=' + cluster_key, auth=(user,password), verify=False)
aggrs = json.loads(aggrs_json.text)

if aggrs['status']['code'] != 'SUCCESS':
   print "Failed to get aggr info for cluster: " + clusters['result']['records'][cluster_num]['name']
   exit(1)

aggr_total_avail = 0
aggr_total_size  = 0
for aggr_num in range ( 0, int(aggrs['result']['total_records']) ):
   aggr_total_size += aggrs['result']['records'][aggr_num]['size_total']
   aggr_total_avail += aggrs['result']['records'][aggr_num]['size_avail']

data_table = []
for aggr_num in range ( 0, int(aggrs['result']['total_records']) ):
   aggrs['result']['records'][aggr_num]['avail_pct'] = aggrs['result']['records'][aggr_num]['size_avail'] / aggr_total_avail
   data_table.append("['" + aggrs['result']['records'][aggr_num]['name'] + "'," + str(aggrs['result']['records'][aggr_num]['size_avail']) + "]")

html_file = open(html_file_name, 'w')
html_file.truncate()

html_file.write(html_prefix)
html_file.write("\n")
for row in data_table:
   html_file.write( unicode(row) + ',' )
   html_file.write("\n")
html_file.write(html_suffix)
html_file.write("\n")





