# denodo-oneclick
Denodo developer one click install for Docker

## Usage

With the reposetory checked out 

```shell
./install.sh --DENODO_SUPPORT_CI test-ci --DENODO_SUPPORT_SECRET test-secret --DENODO_LIC ./denodo-developer-lic-9.lic
```

Directly from Github

```shell
curl -fsSL https://raw.githubusercontent.com/vfagesgo/denodo-oneclick/main/install.sh | bash  -s -- \
--DENODO_SUPPORT_CI test-ci \
--DENODO_SUPPORT_SECRET test-secret \
--DENODO_LIC ./denodo-developer-lic-9.lic
```

docker ps -a --filter name=denodo-oneclick
docker logs -f denodo-oneclick


### Mandatory parameters
- `--DENODO_SUPPORT_CI <value>`
- `--DENODO_SUPPORT_SECRET <value>`
- `--DENODO_LIC <path>` — path to the Denodo license file

### Optional overrides
Defaults come from `denodo_config.env`; pass any of these to override them:
- `--DENODO_UPDATE <value>`
- `--DENODO_PG_USER <value>`
- `--DENODO_PG_PWD <value>`
- `--DENODO_VDP_USER <value>`
- `--DENODO_VDP_PWD <value>`

### Optional (CLI only)
- `--CLOUDFLARE_TUNNEL_KEY <value>`
- `--mode <docker|local>` — default `docker`; `local` is not implemented yet

## Current status

This is an early iteration: the Docker install mode builds and runs a hello-world placeholder container to validate parameter handling. It does not install Denodo VDP yet.
