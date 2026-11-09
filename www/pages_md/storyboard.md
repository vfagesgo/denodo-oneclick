# Try Denodo: demo storyboard

Version 2, 9 November 2026. Owner: Product Marketing, APAC. For Product Management review.

Scene by scene view of the tours in `try-denodo.md`. Where the two differ, `try-denodo.md` wins: it is generated from the pages. Card copy, times and stages below are taken from `pages/welcome.html`.

Built on `bank_demo` and `pharm_ai` as they exist on the demo instance. No new data sources.

---

## How a visitor gets to a tour

1. **Entry page** (`index.html`). Two industry cards, Crestbank (banking) and Medixit (pharmaceuticals), and a diagram of the AI Data Layer. Choosing a card opens the welcome page for that industry.
2. **Welcome page** (`pages/welcome.html?challenge=<id>`). A context banner names the industry, the diagram is pinned to its data, and a scenario line sets the question. Seven cards: three personas, four use cases. Each has **Start tour**. A returning visitor sees **Resume**.
3. **Readiness.** The tour's three stages, an estimate, and readiness lines that tick through, listing the data the tour uses. Tours without a workspace say so.
4. **Guided workspace.** Data Engineer only, today.
5. **Completion.** What the visitor did, labelled as simulated in the prototype, and two next tours.

With Medixit chosen, the persona cards open `pages/medixit-tour-preview.html?role=<role>`, a starter exercise rather than a guided tour.

---

## The shared scenario

**Crestbank.** One question, answered three ways.

> For Gold and Platinum customers, which loans have payments recorded, and when?

| Role             | Does                    | Walks away with                                                       |
| ---------------- | ----------------------- | --------------------------------------------------------------------- |
| Data Engineer    | Builds the data product | `loan_repayment_360` published and classified in the Data Marketplace |
| Business Analyst | Consumes it             | The answer, exported, and compared with Denodo Assistant              |
| AI Builder       | Turns it into a tool    | An agent of their own that answers the same question through MCP      |

The Analyst and AI Builder tours start from a shared copy of `loan_repayment_360`. The Engineer builds into a personal folder, so the tours can be taken in any order.

**Data and endpoints the tours use**

| Asset                                 | Where it comes from                                                                                               |
| ------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `customers`, `loans`, `loan_payments` | interface views in `bank_demo`, folder `/3 - data products`, data source `bank`                                   |
| associations                          | customers to loans on `customer_id`; loans to loan_payments on `loan_id`                                          |
| `pii_data` tags                       | on `last_name`, `email`, `phone_number`, `address`, `dob` in `customers`                                          |
| `ai_banking` and `mcp` tags           | `ai_banking` on all nine `bank_demo` interface views; `mcp` on `customers` and four report views                  |
| property groups                       | Data Product Owners and Data Product Details, on the bank views in the Data Marketplace                           |
| agent skills                          | `bank-demo-verified-queries`, `bank-demo-customer-360`, `bank-demo-best-customer-report`, in the Data Marketplace |
| `bank_demo_rest_ws`                   | REST web service publishing seven `bank_demo` views                                                               |
| Denodo MCP Server                     | `/mcp/admin/mcp`, documented on `mcp-api.html`                                                                    |
| Denodo AI SDK                         | `/aisdk/`; Ask a Question at `/chatbot/`                                                                          |

---

## Storyboard A: Data Engineer

**Card.** Federate live data sources, create a data model, add metadata, and publish it as a reusable data product in Denodo, all without writing code. About 10 min.

**Stages.**

1. **Open the governed views.** Add customers, loans and loan_payments to a new view.
2. **Model and describe.** Combine them with the Data Modeling Wizard, add a description and tags.
3. **Publish and classify.** Publish it, then set its classification, certification and owners in the Data Marketplace.

| #   | Screen                   | What the user sees                                                                                                                                                                                  | What the user does                                                                                                                           | How we know it worked                                                                  |
| --- | ------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| 1   | Welcome                  | Three persona cards and four use-case cards                                                                                                                                                         | Clicks Start tour on Data Engineer                                                                                                           | The readiness screen opens                                                             |
| 2   | Readiness                | The three stages, the estimate, and readiness lines: Denodo Platform 9.6 running, `bank` and `banking_rag` connected, Crestbank sample data products loaded, personal workspace folder created      | Clicks Open guided workspace                                                                                                                 | Workspace folder exists on the server                                                  |
| 3   | Design Studio, step 1    | Tree open at `03 Data Products`. Spotlight on `customers`                                                                                                                                           | Selects `customers`                                                                                                                          | View is on the canvas                                                                  |
| 4   | Step 2                   | Spotlight moves to `loans`. Panel explains the declared `customer_id` relationship                                                                                                                  | Selects `loans`                                                                                                                              | Two views on the canvas, Next unlocks                                                  |
| 5   | Step 3                   | Spotlight on `loan_payments`                                                                                                                                                                        | Selects `loan_payments`                                                                                                                      | Three views on the canvas                                                              |
| 6   | Step 4                   | Spotlight on the Data Modeling Wizard (File > New > Data Model)                                                                                                                                     | Describes the view in plain English. The wizard reads the views' metadata and declared associations and joins on `customer_id` and `loan_id` | Derived view exists. **First visible result:** a 4 row preview                         |
| 7   | Step 5                   | Metadata form. Name prefilled `loan_repayment_360`                                                                                                                                                  | Writes a business description, selects `ai_banking` and `mcp`                                                                                | Description of 15 characters or more saved on the view                                 |
| 8   | Step 6                   | Spotlight on Publish as data product                                                                                                                                                                | Publishes                                                                                                                                    | **Verification:** the published view is read back from the server                      |
| 9   | Step 7, Data Marketplace | The product card with the two property groups every bank product carries, **Data Product Details** and **Data Product Owners**, both with AI usage on. Below them, the agent skills for these views | Sets **Data Classification** to PII / Sensitive and **Certification Tier** to Bronze - Experimental, saves                                   | Property values read back from the Data Marketplace before the tour is marked complete |
| 10  | Completion               | What you actually did, and two next tours: Analyst and AI Builder                                                                                                                                   | Picks one                                                                                                                                    | The next tour opens                                                                    |

**The line that does the work, on step 6.** One definition, one set of permissions, four ways to consume it. This is the step that makes it reusable instead of a one off report.

**Recovery paths**

- Wrong view selected: Next stays locked and the panel names the view still needed. No dead end.
- Wrong classification on step 7: the save is refused and the panel explains why. `customers` is PII / Sensitive and the product includes `last_name`, so the product inherits that classification. A higher certification is refused the same way, because nobody has reviewed the product yet.
- Exit or navigation mid tour: progress is kept in browser storage on the single nginx origin, and Resume reopens the step the visitor left.

---

## Storyboard B: Business Analyst

**Card.** Use Denodo's Data Marketplace to find, review and get analytical insights from data products using natural language. About 8 min.

**Stages.**

1. **Find it.** Search the Data Marketplace and read what the product is for.
2. **Review and request.** Run the question, then request access to a restricted column.
3. **Ask in plain English.** Put the same question to Denodo Assistant and compare.

| #   | Screen              | What the user sees                                                                                                                                                                                                                                                                                           | What the user does                      | How we know it worked                                                                                    |
| --- | ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| 1   | Readiness           | Stages and readiness lines, no modelling tools mentioned                                                                                                                                                                                                                                                     | Opens the Data Marketplace              | Marketplace session established                                                                          |
| 2   | Marketplace, step 1 | Spotlight on the search box; the panel supplies the search term                                                                                                                                                                                                                                              | Searches for the loan repayment product | Product opens                                                                                            |
| 3   | Step 2              | The description, the property groups and the column list. Property groups show the owner, Data Classification PII / Sensitive and the certification tier. The agent skills linked to its source views show which reviewed queries already exist. `pii_data` columns are visible as metadata but not readable | Reads them, expands the column list     | Metadata page viewed                                                                                     |
| 4   | Step 3              | Query panel, filters prefilled for Gold and Platinum                                                                                                                                                                                                                                                         | Runs the query                          | **First visible result:** rows returned                                                                  |
| 5   | Step 4              | A restricted column and the request access control. The Support Contact in Data Product Owners answers it                                                                                                                                                                                                    | Requests access                         | Access request recorded                                                                                  |
| 6   | Step 5              | Export                                                                                                                                                                                                                                                                                                       | Exports to CSV                          | File downloaded                                                                                          |
| 7   | Step 6              | Denodo Assistant with the same question prefilled. In 9.6 the Assistant reads agent skills and property groups as context, so it can follow `bank-demo-verified-queries` and apply any AI rule set in a property group. Its Metadata and Data panels show which views it used                                | Asks it in plain English                | Answer from the same product. The panels list the bank views; the answer matches the analyst's own query |
| 8   | Completion          | The SQL answer and the Assistant answer side by side                                                                                                                                                                                                                                                         | Offered the Data Engineer tour          | The next tour opens                                                                                      |

**The line that does the work, on step 2.** Finding data and being allowed to read it are two different things. You can see every column this product offers. You can only read the ones your role permits.

**Why the Assistant comes last.** If the Assistant answers before the user has run the query, the demo reads as a chatbot demo. Running the query first makes the Assistant a comparison rather than a substitute, and the comparison proves the semantic layer is shared.

---

## Storyboard C: AI Builder

**Card.** Build AI agents and applications using Denodo AI SDK, or connect existing AI agents to governed enterprise data through Denodo MCP Server. About 12 min.

**Stages.**

1. **Expose the tool.** Tag the product mcp so the Denodo MCP Server adds a dedicated tool for it.
2. **Connect your client.** Point VS Code, Claude Desktop or Cursor at the MCP endpoint.
3. **Build and test the agent.** Answer the question, then test the permission boundary.

| #   | Screen                | What the user sees                                                                                                                                                            | What the user does                                                                                                                                | How we know it worked                                                |
| --- | --------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------- |
| 1   | Readiness             | Stages, readiness lines and the MCP endpoint, copyable                                                                                                                        | Copies the endpoint                                                                                                                               | Endpoint copied                                                      |
| 2   | Design Studio, step 1 | Tag field of `loan_repayment_360`                                                                                                                                             | Adds the `mcp` tag                                                                                                                                | Tag written; the MCP Server adds a dedicated query tool for the view |
| 3   | Step 2                | The view metadata the MCP Server exposes, including the column descriptions written in Design Studio                                                                          | Reads it                                                                                                                                          | **First visible result:** the descriptions an agent will read        |
| 4   | Step 3                | The MCP and API page, with the client configuration blocks                                                                                                                    | Pastes the configuration into their own client                                                                                                    | Client connects                                                      |
| 5   | Step 4                | `bank-demo-verified-queries` in the Data Marketplace: ten reviewed VQL templates. Query 3 ranks customers by amount repaid, joining `loan_payments` to `loans` to `customers` | Installs the skill in their own client: in Claude Desktop, uploads the zip; in Claude Code or Cursor, copies the folder into the skills directory | The skill is listed in the client                                    |
| 6   | Step 5                | Their client, not ours. The panel supplies the question: which Gold and Platinum customers have repaid the most                                                               | Asks it                                                                                                                                           | Tool call visible, the agent uses verified query 3, rows returned    |
| 7   | Step 6                | The panel asks for a PII column                                                                                                                                               | Asks for customer surnames                                                                                                                        | The call is refused or masked                                        |
| 8   | Step 7, optional      | The AI SDK, for people building an application rather than wiring a client                                                                                                    | Calls `/aisdk/` with the same question                                                                                                            | Same answer through a different interface                            |
| 9   | Completion            | The one fact worth taking away                                                                                                                                                | Offered the Analyst tour                                                                                                                          | The next tour opens                                                  |

**The line that does the work, on step 3.** The description an agent reads is the description the engineer wrote in Design Studio. Governance and documentation are one system here, not two.

**Why the skill step matters.** Without the skill, the agent writes its own join and its own definition of "repaid the most". With it, the agent uses a definition a data steward already reviewed. That is the difference between an agent that answers and an agent whose answer you can defend.

**Ask a Question.** The tour has the AI Builder build and test their own agent. Ask a Question stays in the navigation as a working example of a finished agent.

---

## A note on the times shown

Every card shows "About N min". Each is an estimate from the number of steps. Replace it with a measured time once the tour is built.
