# MCP & API Services

## Introduction
Denodo Platform also provides a large number of additional data access services including:

* MCP Services
    - VDP MCP - Schema introspection and VQL execution)
    - AI-SDK - Natural Language query
* REST-APIs
    - AI-SDK - Stateless Text to VQL REST service
    - Data Marketplace
    - Graph-QL
    - VDP RESTful 
* SQL Query
    - JDBC
    - ODBC

## MCP Services


### VDP MCP
**The Denodo MCP Server provides:**
- Read-only access to Denodo databases
- The following MCP resources:
    - A resource describing the complete metadata of the database.
    - Individual resources to describe the metadata of each individual view.
- The following MCP tools:
    - Semantic search tool for metadata retrieval.
    - Tool to list all available views.
    - Tools to retrieve schema information for individual views
    - Tools for executing and validating VQL queries.
    - Dedicated query tools for views marked with a configurable tag (deprecated).
    - Tag-based metadata visibility, which can include views from multiple databases (cross-database visibility).

**MCP Endpoint: http://localhost/mcp/admin/mcp**

### AI-SDK MCP
 
You can connect the AI-SDK as an MCP server (i.e, as tools) with your MCP-compatible client (Visual Studio Code, Claude Desktop, Cursor…) via remote MCP (HTTP).

**AI-SDK MCP Endpoint: http://localhost/aisdk/mcp**

### Sample Dynamic Client Registration (DCR)

```json
{
  "servers": {
    "Denodo_AI_SDK_Remote": {
      "url": "<mcp_endpoint>",
      "headers": {
        "Authorization": "Basic YWRtaW46YWRtaW4="
      }
    }
  }
}
```

VS Code configuration with DCR enabled

```json
{
  "inputs": [
    {
      "type": "promptString",
      "id": "denodo_oauth_token",
      "description": "Denodo OAuth 2.0 Token",
      "password": true
    }
  ],
  "servers": {
    "Denodo_AI_SDK_Remote": {
      "url": "<mcp_endpoint>",
      "type": "http",
      "headers": {
        "Authorization": "Bearer ${input:denodo_oauth_token}"
      }
    }
  }
}
```




## REST-APIs

### AI-SDK REST-API

#### Key features
- **Text-to-VQL:** Automatically translates natural language questions into Denodo Virtual Query Language (VQL), allowing AI agents to query the Denodo Platform directly without manual SQL/VQL coding.
- **Metadata Search (RAG):** Uses vectorization to index and search through your technical and business metadata. This enables agents to find the right data assets instantly using semantic search.
- **DeepQuery Agent:** A sophisticated research agent that orchestrates complex tasks. It crafts a multi-step execution plan and carries it out by combining metadata discovery with live VQL data extraction.
- **Model & Vector Store Agnostic:** Provides a flexible architecture to configure and switch between various LLMs and Vector Databases depending on your performance and privacy requirements.

#### AI-SDK API Swagger documentation 
http://localhost/aisdk/docs

### Data Marketplace

The Data Marketplace provides a REST API to perform programmatically all the tasks available in the GUI.

#### DM API Swagger documentation 
http://localhost/denodo-data-catalog/swagger-ui/index.html

### Graph-QL

Denodo GraphQL Service enables the execution of GraphQL queries against the Denodo virtual data model, allowing graphQL-like queries on top of any data source.

**GraphQL Endpoint:  http://localhost/denodo-graphql-service/graphql/<database>/schema.json**

**Examples of how to invoke the GraphQL Endpoint:**

- http://localhost/denodo-graphql-service/graphql/bank_demo/schema.json
- http://localhost/denodo-graphql-service/graphql/medixit/schema.json

### VDP RESTful

The RESTful Web service of the Denodo Platform is an HTTP service that publishes the contents of the entire Virtual DataPort server.

**RESTful web service Endpoint:  http://localhost/denodo-restfulws/<database>/schema.json**

**Examples of how to invoke the RESTful Web service**

- http://localhost/denodo-restfulws/admin returns the list of views of the database admin.

- http://localhost/denodo-restfulws/admin/views/customer returns the content of the view customer of the database admin.

- http://localhost/denodo-restfulws/admin/views/customer/1/orders browses through the mapping orders of the row of the table customer whose primary key is 1.

- http://localhost/denodo-restfulws/OpenAPIv3/openapi.json returns the OpenAPI 3 document describing the available operations in JSON format.

- http://localhost/denodo-restfulws/OpenAPIv3/openapi.yaml?database=db1&database=db2&tag=tag1&tag=tag2 returns the OpenAPI 3 document describing the available operations in YAML format for the views in databases db1 or db2 with tags tag1 or tag2.

## SQL Query

### Access Through JDBC
Denodo provides a JDBC Type 4 driver that implements the main characteristics of the JDBC 4.1 API (Java Database Connectivity). This means that the driver is platform independent.

Get the Denodo JDBC driver from:

The Denodo Community: https://community.denodo.com/drivers/jdbc/. You need to register on this site to download it (anyone can register).

You can also find the JDBC driver in the installation of the Denodo Platform (<DENODO_HOME>/tools/client-drivers/jdbc/vdp-jdbcdriver-core/denodo-vdp-jdbcdriver.jar).

**Driver Class Name:** `com.denodo.vdp.jdbc.Driver`

**Connection URL:** `jdbc:denodo://<hostname>[:<port>]/[<database>][?<paramName>=<paramValue>[&<paramName>=<paramValue>]*]`

### Access Through ODBC
Denodo provides an ODBC driver for Windows and Linux and it also provides the source code to build the driver for other platforms. This driver is based on the ODBC PostgreSQL driver version 16.00.

Refer to the Denodo documentation for more information