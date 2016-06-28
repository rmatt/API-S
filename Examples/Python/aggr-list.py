#!/usr/bin/python


import getpass
import warnings
import requests
import json
warnings.filterwarnings('ignore', 'Unverified HTTPS request')

url = raw_input("Enter the base URL (e.g. https://10.0.0.227:8443/api/1.0/ontap): ")
user = raw_input('Enter admin user name: ')
password = getpass.getpass('Enter password: ')

clusters_json = requests.get(url + '/clusters', auth=(user,password), verify=False)
aggrs_json = requests.get(url + '/aggregates', auth=(user,password), verify=False)

clusters = json.loads(clusters_json.text)
for cluster in clusters['result']['records']:
   print cluster['name']
   cluster_key = cluster['key']
   nodes_json = requests.get(url + '/nodes?cluster_key=' + cluster_key, auth=(user,password), verify=False)
   nodes = json.loads(nodes_json.text)
   for node in nodes['result']['records']:
      print "\t" + node['name']
      node_key = node['key']
      aggrs_json = requests.get(url + '/aggregates?node_key=' + node_key, auth=(user,password), verify=False)
      aggrs = json.loads(aggrs_json.text)
      for aggr in aggrs['result']['records']:
         if aggr['size_avail_percent']:
            free_space_pct = aggr['size_avail_percent']
         else:
            free_space_pct = 0
         print "\t\t" + aggr['name'] + " Free Space: " + str(free_space_pct)


