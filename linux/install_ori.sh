curl --request 'POST' \
  --header 'accept: */*' \
  --header 'Authorization: Basic YWRtaW46YWRtaW4=' \
  --header 'Content-Type: application/json' \
  --header 'uri: //localhost:9999/admin' \
  --header 'serverId: 1' \
  --data '{
    "allServers": "true",
    "priority": "server"
  }' \
"http://localhost:9090/denodo-data-catalog/public/api/element-management/all/synchronize/all-servers"