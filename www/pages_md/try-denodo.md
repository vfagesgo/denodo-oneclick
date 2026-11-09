---
spec: try-denodo-frontend
version: 3
updated: '2026-11-09'
owner: Product Marketing, APAC
status: For Product Management review.
target: vfagesgo/denodo-oneclick, wip branch, www/
entry_page:
  file: index.html
  heading: What would you like to work on?
  subtitle: Pick an industry scenario. We will set up a guided Denodo experience around it.
  logo: images/denodo_logo_black.png, header top left
  skip_link: index_v3.html?challenge=crestbank
  cards:
  - id: crestbank
    title: Crestbank
    tag: Banking
    copy: Help a bank understand repayment activity among its Gold and Platinum customers.
    footer: Customer and loan data
    image: images/card-banking.jpg
    route: index_v3.html?challenge=crestbank
  - id: medixit
    title: Medixit
    tag: Pharmaceuticals
    copy: Help a pharmaceutical company understand patient participation, study start dates
      and the X-ray images linked to trial patients.
    footer: Clinical-trial and X-ray data
    image: images/card-pharma.jpg
    route: index_v3.html?challenge=medixit
  diagram:
    style: 'Flowise-inspired light canvas inside a card: toolbar with the Denodo logo, title
      "One data layer. Many possibilities." and a Banking / Pharma toggle; dotted canvas;
      caption with step number, step text and the business question; four step buttons'
    columns: sources, AI Data Layer, data product, consumers (no column labels)
    sources:
      Banking:
      - Traditional DB & DW (Core systems)
      - SaaS apps (CRM & service)
      - Streaming (Payments events)
      Pharma:
      - Files (X-ray images)
      - Lakehouse (Research platform)
      - SaaS (Clinical apps)
    centre: 'official Denodo logo, "AI Data Layer", subtitle "Active context, powered by Denodo",
      rows are the four Denodo pillars: Universal Connectivity; Zero-Copy Delivery; Governed
      Access; Semantic Trust; footer Active context'
    product:
      Banking: loan_repayment_360
      Pharma: i_clinical_trials_patients_start_date
    consumers:
    - Data Marketplace
    - Analytics & data science
    - Data as a Service (REST, OData, GraphQL)
    - AI (MCP, AI SDK, agent skills)
    questions:
      Banking: Which Gold and Platinum customers have loan payments recorded, and when?
      Pharma: How many patients joined each trial, and when did their studies begin?
    motion: steps advance every 3.2 seconds and the scenario alternates after step 4; step
      buttons jump to a step; no pause control; stops for prefers-reduced-motion and while
      the tab is hidden
    layouts: fits its frame at 1024px and wider; scrolls sideways below that, with a hint
    note: illustration only
welcome_page:
  file: index_v3.html
  title: Welcome to your Denodo trial!
  logo: images/denodo_logo_black.png, left navigation top left
  scenario_line:
    crestbank: Crestbank wants to understand loan repayment activity among Gold and Platinum
      customers. Choose the role you want to play in answering this question.
    medixit: Medixit wants to understand patient participation, study start dates and the
      X-ray images linked to trial patients. Choose the role you want to play in answering
      this question.
    source: challenge-context.js, written into the element marked data-scenario-line
  section_heading: Choose a tour and get hands on in a few minutes!
  usecase_heading: Or choose a tour by use case
type:
  font_stack: '"Proxima Nova", "proxima-nova", Roboto, sans-serif'
  font_source: matches community.denodo.com
  webfonts: www/fonts/Proxima Nova/ (already in the repository)
external_assets: none
works_offline: true
nav:
- label: Get started
  href: '#'
- label: Design Studio
  href: /denodo-design-studio/
- label: Data Marketplace
  href: /denodo-data-catalog/#/
- label: Ask a Question
  href: /chatbot/
- label: MCP and API
  href: mcp-api.html
- label: Documentation
  href: documentation.html
cards:
- id: analyst
  group: persona
  title: Business Analyst
  copy: Use Denodo's Data Marketplace to find, review and get analytical insights from data
    products using natural language.
  time: 8 min
  image: images/persona-analyst.jpg
- id: engineer
  group: persona
  title: Data Engineer
  copy: Federate live data sources, create a data model, add metadata, and publish it as a
    reusable data product in Denodo, all without writing code.
  time: 10 min
  image: images/persona-engineer.jpg
- id: ai
  group: persona
  title: AI Builder
  copy: Build AI agents and applications using Denodo AI SDK, or connect existing AI agents
    to governed enterprise data through Denodo MCP Server.
  time: 12 min
  image: images/persona-ai.jpg
- id: context
  group: usecase
  title: Deliver Active Context for AI
  copy: Ensure that AI gets reliable, live information to make a correct choice!
  time: 10 min
  icon: spark
- id: lakehouse
  group: usecase
  title: Optimize your Lakehouse
  copy: Explore how Denodo helps a banking agent satisfy customer needs by federating the
    right data at the right time!
  time: 7 min
  icon: db
- id: share
  group: usecase
  title: Use and Share Data Products
  copy: Publish and share governed data products through Denodo Data Marketplace, SQL and
    REST APIs for consumption by analysts and applications.
  time: 8 min
  icon: net
- id: aws
  group: usecase
  title: Seamless Application modernization with AWS and Denodo
  copy: Guide a migration team as a legacy system moves to Amazon Aurora. Ensure that passenger
    experience on a flight is not negatively impacted due to the migration!
  time: 9 min
  icon: cloud
---

# Try Denodo: front end and guided tours

**Status: for Product Management review.** Cards, times, animation data and Data Engineer steps in this document are generated from `index_v3.html` and `index.html`, so the document and the pages match.

Two fictional customers. **Crestbank** runs on `bank_demo` and carries the three persona tours. **Medixit** runs on `pharm_ai`; choosing it routes the persona cards to a starter exercise page.

## Files

```
www/index.html                    industry entry page
www/index_v3.html                 welcome page, readiness, guided workspace, completion
www/challenge-context.css / .js   carries the chosen industry into index_v3.html
www/medixit-tour-preview.*        Medixit starter exercise page
www/images/card-banking.jpg, card-pharma.jpg
www/images/persona-analyst.jpg, persona-engineer.jpg, persona-ai.jpg
www/images/denodo_logo_black.png, denodo_logo_white.svg
```

No external scripts, fonts or CDN. Works offline. Native browser dialogs are not used anywhere.

## Journey

| Step | Screen | Notes |
|---|---|---|
| 1 | Entry page, `index.html` | Two industry cards. Choosing one opens `index_v3.html?challenge=<id>` |
| 2 | Welcome page | Context banner shows the industry. The animation is pinned to its dataset. The scenario line switches per industry |
| 3 | Readiness | Shows the tour's three stages, an estimate, and readiness lines and a diagram for the data the tour uses: `pharm_ai` for the two Medixit use cases, `bank_demo` for every other tour. Tours other than Data Engineer state that their workspace is not built yet |
| 4 | Guided workspace | Data Engineer only. Next stays disabled until the step is done |
| 5 | Completion | States what was done. Labels publication as simulated in the prototype |

With Medixit chosen, persona cards route to `medixit-tour-preview.html?role=<role>`.

## Industry context contract

`challenge-context.js` reads `?challenge=` (falling back to session storage, then Crestbank), shows the context banner, writes the industry's scenario line into the element marked `data-scenario-line`, and exposes `window.TryDenodoChallenge` with the id, label and database. `index_v3.html` reads the same parameter to pin the animation dataset.

## Welcome page animation

Each loop shows one industry: connected sources (the same source types as the entry-page diagram), governed views, the data product, and four ways to reach it.

```yaml
animation:
  type: illustration of the product, not a live view
  step_ms: 780
  dataset_selection: pinned by ?challenge=, alternates when absent
  reduced_motion: renders the finished end state, paused
  tabs:
  - Sources
  - Model
  - Marketplace
  - Services
  consumers:
  - Data Marketplace
  - SQL
  - REST service
  - MCP tool
  datasets:
  - who: Crestbank
    sources:
    - name: Traditional DB & DW
      detail: Core systems
    - name: SaaS apps
      detail: CRM & service
    - name: Streaming
      detail: Payments events
    views:
    - name: customers
      tags:
      - mcp
      - pii_data
    - name: loans
      tags:
      - ai_banking
    - name: loan_payments
      tags:
      - ai_banking
    data_product:
      name: loan_repayment_360
      tags:
      - mcp
      - ai_banking
  - who: Medixit
    sources:
    - name: Files
      detail: X-ray images
    - name: Lakehouse
      detail: Research platform
    - name: SaaS
      detail: Clinical apps
    views:
    - name: patients
      tags:
      - medixit_ai
    - name: clinical_trials
      tags:
      - medixit_ai
    - name: common_date
      tags:
      - medixit_ai
    data_product:
      name: i_clinical_trials_patients_start_date
      tags:
      - ai_ready
```

## Shared scenario for the three personas

> For Gold and Platinum customers, which loans have payments recorded, and when?

| Role | Does | Walks away with |
|---|---|---|
| Data Engineer | Builds `loan_repayment_360` | The product published in the Data Marketplace |
| Business Analyst | Consumes it | The answer, exported, and compared with Denodo Assistant |
| AI Builder | Exposes it to an agent | Their own client answering the same question through MCP |

The Analyst and AI Builder tours start from a shared copy of `loan_repayment_360`. The Engineer builds into a personal folder, so the tours can be taken in any order.

**Data and endpoints the tours use**

| Asset | Fact |
|---|---|
| `customers`, `loans`, `loan_payments` | interface views in `bank_demo`, folder `/3 - data products`, all from source `bank` |
| associations | customers to loans on `customer_id`; loans to loan_payments on `loan_id` |
| `pii_data` | column tag on `last_name`, `email`, `phone_number`, `address`, `dob` in `customers` |
| `ai_banking` | view tag on all nine `bank_demo` interface views |
| `mcp` | view tag on `customers` only, plus four report views |
| `bank_demo_rest_ws` | REST web service publishing seven `bank_demo` views |
| Denodo MCP Server | `/mcp/admin/mcp`, documented on `mcp-api.html` |
| Denodo AI SDK | `/aisdk/`; Ask a Question at `/chatbot/` |

## Tour: Data Engineer

Implemented in the prototype. In production, step e6 completes only when the published view is read back from the server.

```yaml
tour: engineer
title: Data Engineer
application: Design Studio
customer: Crestbank
database: bank_demo
estimated: 10 min
stages:
- name: Open the governed views
  detail: Add customers, loans and loan_payments to a new view.
- name: Model and describe
  detail: Combine them with the Data Modeling Wizard, add a description and tags.
- name: Publish and classify
  detail: Publish it, then set its classification, certification and owners in the Data Marketplace.
steps:
- id: e1
  stage: 1
  target: '[data-v="customers"]'
  title: Start with the customer view
  body: Under 03 Data Products, select customers. It comes from the bank data source and is
    already described field by field.
  why: Nothing is imported or copied. The view is a definition that reads from the source
    when queried.
  task: Select customers in the tree
  completion: view customers present on the canvas
- id: e2
  stage: 1
  target: '[data-v="loans"]'
  title: Add the loans view
  body: Now select loans. Each loan carries a customer_id, so Denodo already knows how these
    two relate.
  why: The relationship is declared once, in the model, not rewritten in every report that
    needs it.
  task: Select loans in the tree
  completion: view loans present on the canvas
- id: e3
  stage: 1
  target: '[data-v="loan_payments"]'
  title: Add repayment history
  body: Add loan_payments. This is what turns a list of loans into a question you can answer
    about repayment behaviour.
  why: Three views, one query, no staging table in between.
  task: Select loan_payments in the tree
  completion: view loan_payments present on the canvas
- id: e4
  stage: 2
  target: '#btn-wizard'
  title: Combine them with the Modeling Wizard
  body: 'Open the Data Modeling Wizard (File > New > Data Model) and describe what you
    need in plain English. It reads the views'' metadata and the associations declared in
    bank_demo, so the join keys come from the model: customer_id and loan_id.'
  why: The result is one logical view. Denodo decides at query time how much work each source
    does.
  task: Run the Data Modeling Wizard
  completion: derived view created
  first_visible_result: 4 row preview of the combined view
- id: e5
  stage: 2
  target: '#meta'
  title: Describe it for the next person
  body: Name the view and write a description saying what it answers and what it must not
    be used for. Tag it ai_banking and mcp so MCP clients get a dedicated tool for it.
  why: This description is what an analyst reads in the Marketplace and what an agent reads
    over MCP. Undocumented products do not get reused.
  task: Write a description, then click Save metadata
  completion: description of 15 characters or more saved on the view
- id: e6
  stage: 3
  target: '#btn-publish'
  title: Publish it once, for everyone
  body: Publish as a data product. The same definition is now reachable through the Marketplace,
    SQL, the REST service and MCP.
  why: One definition, one set of permissions, four ways to consume it. This is the step that
    makes it reusable instead of a one off report.
  task: Click Publish as data product
  completion: published view read back from the server
- id: e7
  stage: 3
  target: '#pg'
  title: Complete its product card
  body: In the Data Marketplace, fill in the property groups every bank product carries. Choose
    the Data Classification and Certification Tier. Below them are the agent skills already
    written for these views.
  why: Classification and certification tell an analyst how far to trust the product and who
    to ask. Both groups have AI usage on, so Denodo Assistant reads them as context too.
  task: Set both fields, then click Save to Data Marketplace
  completion: Data Product Details and Data Product Owners assigned to the product with Data
    Classification PII / Sensitive and Certification Tier Bronze - Experimental, read back
    from the Data Marketplace property API
```

## Tour: Business Analyst

Specified, not yet implemented. Denodo Assistant comes last on purpose: running the query first makes the Assistant a comparison rather than a substitute.

```yaml
tour: analyst
title: Business Analyst
application: Data Marketplace
customer: Crestbank
database: bank_demo
estimated: 8 min
stages:
- name: Find it
  detail: Search the Data Marketplace and read what the product is for.
- name: Review and request
  detail: Run the question, then request access to a restricted column.
- name: Ask in plain English
  detail: Put the same question to Denodo Assistant and compare.
steps:
- id: a1
  stage: 1
  target: Marketplace search box
  title: Find the data product
  body: Search for the loan repayment data product and open it.
  task: Open loan_repayment_360
  completion: product page opened
- id: a2
  stage: 1
  target: product description and column list
  title: Read what it is for
  body: The description says what the product answers and what it must not be used for. The
    property groups name the owner, the classification (PII / Sensitive) and the certification
    tier. The agent skills linked to its source views show which reviewed queries already
    exist. The column list shows every field.
  task: Expand the column list
  completion: metadata page viewed
- id: a3
  stage: 2
  target: query panel
  title: Run the question
  body: Filter to Gold and Platinum customers and look at the loan payments recorded against
    them.
  task: Run the query
  completion: rows returned
  first_visible_result: rows returned
- id: a4
  stage: 2
  target: restricted column
  title: Request what you cannot see
  body: If a column is restricted for your role, request access to it.
  task: Submit an access request
  completion: access request recorded
- id: a5
  stage: 3
  target: export control
  title: Take the result away
  body: Export to CSV.
  task: Export the result
  completion: file downloaded
- id: a6
  stage: 3
  target: Denodo Assistant
  title: Ask it in plain English
  body: Put the same question to Denodo Assistant and compare the answer with your query.
    In 9.6 the Assistant reads agent skills and property groups as context, alongside descriptions,
    tags and associations, so it can follow the verified repayment query in bank-demo-verified-queries
    and apply any AI rule set in a property group.
  task: Ask the question in natural language
  completion: answer returned from the same product
```

## Tour: AI Builder

Specified, not yet implemented. The AI Builder builds and tests their own agent. Ask a Question stays in the navigation as a working example.

```yaml
tour: ai
title: AI Builder
application: Design Studio, then the user's own MCP client
customer: Crestbank
database: bank_demo
estimated: 12 min
stages:
- name: Expose the tool
  detail: Tag the product mcp so the Denodo MCP Server adds a dedicated tool for it.
- name: Connect your client
  detail: Point VS Code, Claude Desktop or Cursor at the MCP endpoint.
- name: Build and test the agent
  detail: Answer the question, then test the permission boundary.
steps:
- id: i1
  stage: 1
  target: tag field on loan_repayment_360
  title: Expose the product as a tool
  body: Add the mcp tag to the data product.
  task: Add the mcp tag
  completion: tag written to the view
- id: i2
  stage: 1
  target: tool definition
  title: Read what the agent will see
  body: The descriptions an agent reads come from the view's own column descriptions, written
    in Design Studio.
  task: Inspect the tool definition
  completion: definition displayed
- id: i3
  stage: 2
  target: MCP and API page
  title: Connect your own client
  body: Point an MCP capable client at /mcp/admin/mcp using the configuration on the MCP and
    API page.
  task: Connect VS Code, Claude Desktop or Cursor
  completion: client connects and lists the tool
- id: i4
  stage: 2
  target: Agent Skill Server, bank-demo-verified-queries
  title: Give the agent its skill
  body: Load bank-demo-verified-queries. It holds ten reviewed VQL templates; query 3 ranks
    customers by amount repaid through loans to loan_payments. The agent fills in the template
    instead of writing its own join.
  task: 'Find the skill in the Data Marketplace and install it in your client (Claude Desktop:
    upload the zip; Claude Code or Cursor: copy the folder into the skills directory)'
  completion: the agent cites verified query 3 when it answers
- id: i5
  stage: 3
  target: the user's client
  title: Ask the business question
  body: Ask it in plain English and watch the tool call.
  task: Run the question through the agent
  completion: tool call visible, rows returned
- id: i6
  stage: 3
  target: the user's client
  title: Test the boundary
  body: Ask for customer surnames.
  task: Request a restricted column
  completion: the call is refused or the column is masked
- id: i7
  stage: 3
  optional: true
  target: AI SDK
  title: Or build on the AI SDK instead
  body: For an application rather than a client, call /aisdk/ with the same question.
  task: Call the AI SDK
  completion: the same answer through a different interface
```

## Use case tours

Cards and readiness screens only. Their guided workspaces are not part of this release.

```yaml
- tour: context
  title: Deliver Active Context for AI
  estimated: 10 min
  stages:
  - 'Search X-rays and trial data together: Find trial patients whose X-ray descriptions match
    a finding, in one query.'
  - 'Two roles, one question: Compare what each role is allowed to see.'
  - 'Change the source, ask again: Update one enrolment record and watch the answer follow.'
  readiness_screen: 'sec_clinical_trials and snowflake_pharma connected; Medixit clinical-trial
    and X-ray data loaded; diagram: clinical_trials, patients, xray_analysis_embedding to
    iv_xray_images'
- tour: lakehouse
  title: Optimize your Lakehouse
  estimated: 7 min
  stages:
  - 'The lakehouse list: Top customers by propensity score.'
  - 'Apply current reality: Arrears, dormancy and consent remove four of them.'
  - 'Decide: The governed decision view, and what it cost to run.'
  readiness_screen: 'bank and banking_rag connected; Crestbank sample data products loaded;
    diagram: customers, loans, loan_payments to loan_repayment_360'
- tour: share
  title: Use and Share Data Products
  estimated: 8 min
  stages:
  - 'Discover: Inspect the product and its documentation.'
  - 'Query it in SQL: Run it from Design Studio.'
  - 'Call it as REST: Hit the published service and compare.'
  readiness_screen: 'sec_clinical_trials and snowflake_pharma connected; Medixit sample data
    products loaded; diagram: clinical_trials, patients, common_date to i_clinical_trials_patients_start_date'
- tour: aws
  title: Seamless Application modernization with AWS and Denodo
  estimated: 9 min
  stages:
  - 'Before the move: The application reads the contract, not the legacy database.'
  - 'During the cutover: Switch the underlying source while the contract stays fixed.'
  - 'After the move: Same questions, same answers, new system underneath.'
  readiness_screen: 'bank and banking_rag connected; Crestbank sample data products loaded;
    diagram: customers, loans, loan_payments to loan_repayment_360'
```

## Prototype note

The pages do not call Denodo. The Data Engineer workspace simulates Design Studio and the Data Marketplace product card, and the completion screen labels publication as simulated. The diagrams are illustrations. Times are estimates.
