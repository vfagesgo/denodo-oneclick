curl --request 'GET' \
  --header 'accept: */*' \
  --user "admin:admin" \
  --header 'Content-Type: application/json' \
  -H 'vdp_tag_names: ai_ready' \
"http://localhost:8008/getMetadata?vdp_tag_names=ai_ready"


curl --request 'GET' \
  --header 'accept: */*' \
  --user "admin:admin" \
  --header 'Content-Type: application/json' \
"http://localhost:8008/getVectorDBInfo"

curl --request 'GET' \
  --header 'accept: */*' \
  --user "admin:admin" \
  --header 'Content-Type: application/json' \
"http://localhost:8008/getMetadata?vdp_tag_names=ai_ready"




curl --request 'POST' \
  --header 'accept: */*' \
  --user "admin:admin" \
  --header 'Content-Type: application/json' \
  --header 'uri: //localhost:9999/admin' \
  --header 'serverId: 1' \
  --data '{
  "vdpTags": [
    "ai_ready"
  ]
}' \
"http://localhost:9090/denodo-data-catalog/public/api/tags/vdp/synchronize"

/public/api/tags/vdp/synchronize