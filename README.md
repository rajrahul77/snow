4.2 Use Case 2: Denodo MCP Layer and Multi-Agent Workflow System

Use-Case Description

This use case evaluates how Dataiku agents can use enterprise customer data exposed through Denodo MCP, coordinate several specialised agents in one user-facing workflow, and complete that workflow with a human-approved customer email.

The implementation uses the Resort360 customer intelligence dataset. The system identifies a customer-growth opportunity, selects the relevant customers, recommends a next action and, where required, drafts a personalised email. That email is sent only after a person approves it.

The solution is split into specialised agents to evaluate orchestration, context passing, tool usage and control between agents. The same business logic could be implemented with fewer LLM calls; the multi-agent design is there to assess Dataiku's orchestration capabilities, not because the use case requires it.

A general-purpose customer intelligence path is also available, so users are not limited to the growth workflow. Questions such as "Who is the highest-spending customer?" or "Show the top customers by lifetime revenue" are answered directly from the customer data, without running the full chain.

Agents and Responsibilities

Orchestrator Agent

The Orchestrator is the user-facing entry point. It classifies the request, delegates work to the right specialist agent and passes upstream context to downstream agents. It does not analyse customer data itself.

For an end-to-end growth request, the sequence is Portfolio Opportunity Agent → Customer Targeting Agent → Next Best Action Agent → email preparation and approval. For a direct data question, it routes to the General-Purpose Customer Intelligence Agent instead.

The Orchestrator is also the only component allowed to request the email tool. It prepares the recipient, subject and message for each approved customer and requests one send per recipient.

General-Purpose Customer Intelligence Agent

This agent answers factual and analytical questions that do not need the full workflow, such as:

- highest or lowest spending customer;
- top-N customers by revenue;
- booking counts and average customer metrics;
- customer-level lookups;
- segment comparisons, filtering and ranking.

It uses the configured data-access tools and treats structured values as the source of truth, not generated customer summaries.

Portfolio Opportunity Agent

This agent analyses the portfolio and identifies one customer-growth opportunity. It returns the opportunity, target profile, selection logic, supporting evidence, priority and business objective. It does not select individual customers or define the action.

Customer Targeting Agent

This agent receives the opportunity as a fixed input and identifies the customers who meet its criteria. Selection uses observed attributes such as booking count, segment, revenue and stay duration.

For each selected customer it returns the customer ID, name, verified email address from the source data, selection rationale and supporting metrics. The shortlist is capped at 10 customers per run. It must not invent or infer an email address.

Next Best Action Agent

This agent receives the opportunity and the selected cohort and turns them into a practical action and success metric.

It must not invent preferences, discounts, prizes, channels, conversion rates, ROI or campaign targets. Concrete offers appear only when approved campaign information supports them; otherwise it returns a general action.

Email Action (Send Message tool)

Customer emails are sent through a Dataiku Send Message tool, send_email_tool, using the data-platform-mailer (smtp) messaging channel. The tool takes three parameters: recipient, subject and message.

The tool is an action, not an agent. It performs no reasoning, and every call passes through a human approval step before it runs.

Workflow and Agent Interaction

The Orchestrator first classifies the request. A direct analytical question goes to the General-Purpose Customer Intelligence Agent and skips the chain. A customer-growth request runs as follows:

1. The Portfolio Opportunity Agent identifies an opportunity.
2. The Orchestrator checks that the opportunity, target profile, selection logic and objective are consistent.
3. The Customer Targeting Agent receives the full opportunity and returns matching customers with verified email addresses.
4. The Next Best Action Agent receives the opportunity and cohort and returns the action and success metric.
5. If the request includes outreach, the Orchestrator drafts one email per selected customer as plain text, using only verified customer fields and approved campaign content.
6. The approval interface shows the recipient, subject and message, and the user accepts or rejects each email.
7. On acceptance, send_email_tool sends the email through the SMTP channel. A rejected email is not sent.
8. The Orchestrator reads the tool result, records the outcome per recipient and stops. It does not retry automatically.
9. The Orchestrator returns one consolidated response, including the send status for each recipient.

If the request asks only for a recommendation, the workflow ends at step 4 and no email is drafted.

Architecture and Data Flow

The architecture has five layers:

- Data layer: customer intelligence data held in Denodo and represented in the Dataiku project.
- Tool layer: Denodo MCP for dynamic queries; dataset lookup or SQL access for deterministic verification and aggregation.
- Agent layer: specialised agents for portfolio analysis, targeting, direct analytics and next best action.
- Orchestration layer: the Orchestrator as the single user-facing entry point, which coordinates agents and prepares email parameters.
- Action layer: send_email_tool, gated by human approval, sending through the data-platform-mailer (smtp) channel.

The Orchestrator does not need direct Denodo access. Data access stays with the analytical agents, and the ability to send stays with the Orchestrator.

Tools

Tool | Used by | Purpose
Denodo MCP | Analytical agents | Controlled access to Resort360 customer data for segment analysis, high-value customer identification, booking and revenue retrieval
Dataset lookup / SQL access | Analytical agents | Deterministic answers for max, min, top-N, counts, averages and rankings, and exact record validation
send_email_tool (Send Message) | Orchestrator | Sends one approved email per call, with recipient, subject and message

For deterministic questions, direct dataset or SQL access is preferred because the result comes from structured data rather than LLM inference.

Agent-to-Agent Context Sharing

Outputs are passed explicitly between stages; no downstream agent is assumed to know earlier decisions.

The Customer Targeting Agent receives the full opportunity output. The Next Best Action Agent receives both the opportunity and the targeting result. The email step receives the selected customers' verified name and email address plus the approved action, and nothing else.

Downstream agents are instructed not to change upstream decisions such as the selected cohort or business objective. This makes each recommendation and each email traceable to the data behind it.

Email Automation

Email content and email presentation are handled in separate layers. Mixing them caused the initial formatting problem: Markdown markers such as **bold** appeared literally in received emails, and the body arrived as one dense paragraph.

- Content layer (agent): the Orchestrator writes plain text only, with no Markdown, asterisks or HTML. It uses short paragraphs, a greeting, a concise introduction, numbered steps where needed and a professional closing.
- Presentation layer (tool template): the Send Message body template wraps that text in an HTML layout with a branded header, a container about 600 px wide, readable spacing and a short footer. The message is HTML-escaped and line breaks are converted, so generated text cannot break the layout.

With this split, test emails render correctly in the recipient mailbox.

The parameter mapping is:

Parameter | Source
recipient | The selected customer's email field in the source data, never generated text
subject | Written by the Orchestrator for the approved action
message | The full plain-text body, including the greeting, so the name is not duplicated by the template

Human Approval Points

Human approval is enforced before any email is sent. For each proposed email, the interface shows the recipient, subject and full message, and the user must accept or reject it. Nothing is sent without acceptance.

This control stays enabled in all environments. Removing it or sending automatically would require an explicit change in requirements and a separate review.

Recommendations themselves do not need approval, because they trigger no customer-facing action.

Error Handling and Recovery

The Orchestrator is the control point between agents and before the email action. Current rules:

- retry a specialist agent when required fields are missing;
- stop the workflow when no meaningful opportunity is found;
- stop when no customers meet the targeting criteria;
- do not create an action, or an email, without a valid target cohort;
- skip any customer without a verified email address in the source data;
- treat structured data as the source of truth when it conflicts with generated text;
- return "insufficient information" rather than fill gaps with assumptions.

For the email action, each stage is checked separately, because success at one stage does not prove the next:

1. The Orchestrator requests the tool.
2. The approval request is shown, and the user accepts or rejects.
3. The tool runs and the SMTP service accepts or rejects the message.
4. The message is delivered, deferred or bounced by the recipient's provider.

A "call accepted" message confirms only the first stages. The Orchestrator makes at most one send request per recipient per run. An uncertain send is not retried automatically, because the first email may already have been delivered. Failures are investigated through the tool output and SMTP or provider logs; an earlier SMTP authentication error (451 Authentication failed) was resolved this way.

Security and Governance

Data access is separated from orchestration, and the ability to send is separated from data access. Only analytical agents hold MCP or dataset tools; only the Orchestrator can request send_email_tool.

Structured customer fields are the source of truth. Generated insight fields are supporting context only and never supply a recipient, a metric or eligibility.

Personal data not needed for a stage is not passed to it; the email step receives only the name, address and approved action. Campaign details, offers and dates in an email must come from approved campaign content.

Agent Hub is the user-facing access layer, so the specialist agents and the email tool are not exposed to business users directly.

Test Scenarios

The workflow was tested with end-to-end business requests, direct analytical questions and email actions.

- identify a growth opportunity and recommend the next best action;
- identify actual customers matching an opportunity;
- determine the highest-spending customer and the top customers by lifetime revenue;
- compare repeat and standard customers;
- verify that selected customers meet the upstream criteria;
- check whether the Next Best Action Agent introduces unsupported offers or assumptions;
- check that the Orchestrator takes the direct path for simple questions;
- generate an email for a selected customer and confirm the recipient matches the source data;
- approve one email and confirm it reaches an authorised mailbox with correct formatting;
- reject a proposed email and confirm nothing is sent;
- confirm the email tool is requested once per recipient.

Results and Observations

The PoC showed that Dataiku can coordinate multiple agents, keep their responsibilities separate and end the workflow with a governed external action.

- Context passing: when upstream output was not passed explicitly, downstream responses became generic or introduced assumptions.
- Strict prompts: tighter instructions reduced unsupported statements, especially in the Next Best Action stage.
- Direct path: rankings, counts and lookups are better handled by the general-purpose path than by the full chain.
- Deterministic data: factual values should be queried, not generated; LLM reasoning adds value in interpreting them.
- Email delivery: end-to-end sending was demonstrated to a real mailbox after an SMTP authentication issue was resolved.
- Email formatting: separating plain-text generation from the HTML template fixed the literal Markdown and layout problems.
- Approval: the approval step worked as intended, showing the populated recipient, subject and message before each send.
- Repeated calls: in one earlier run, the interface showed about nine "call accepted" entries for send_email_tool, suggesting repeated requests. Later runs showed a single approval request. This needs to be re-validated.

Scalability and Operational Considerations

The implementation is a PoC built to validate orchestration patterns, not production throughput.

A multi-agent request makes several LLM and tool calls, adding latency and token cost compared with a single agent. The Orchestrator therefore invokes only the agents a request needs, and direct questions skip the chain.

Email adds a per-recipient approval step, so the 10-customer cap also bounds the reviewer's workload. Before scaling, evaluate concurrency, MCP query performance, LLM cost, timeouts, logging volume, the number of records passed between agents and mail-provider sending limits.

Risks and Limitations

- Descriptive data: without a predictive model, the system must not describe customers as "likely to convert" or "high propensity".
- Run-to-run variation: orchestration relies on LLM reasoning, so outputs can vary between runs.
- Added complexity: the multi-agent split adds latency, and parts could be done in a single structured call.
- Data gaps: where channel preference, offer history, campaign response or recency are missing, the system must not infer them.
- Duplicate sends: an orchestrator that repeats a tool call could send the same email twice; approval reduces but does not remove this risk.
- Delivery uncertainty: SMTP acceptance does not guarantee inbox delivery, and recipients' security settings may flag the email as external.
- Content accuracy: an email can contain an incorrect offer or date if campaign content is not approved and supplied to the agent.
- In-chat charts: the chat interface shows chart-style answers as text, because chart generation needs structured tool output that the current Denodo MCP path does not provide.

The value of the design lies in demonstrating controlled delegation, tool usage, context passing and governed actions, not in claiming that multi-agent execution is inherently better.

Recommended Improvements

- Validate customer IDs, metrics and email addresses against the structured dataset before they reach the final response or an email.
- Add a SQL-based analytical tool for aggregation, ranking and top-N questions. Using the SQL Question Answering tool would also enable in-chat chart generation.
- Add an explicit stop condition and a per-run record of recipients already emailed, to prevent duplicate sends.
- Define how failed, rejected and uncertain sends are reported and handled.
- Supply approved campaign content from a governed source instead of the prompt.
- Introduce formal output schemas between agents.
- Add automated evaluation scenarios for common queries, including email cases.
- Monitor tool-call order, agent traces, latency and token use per workflow.
- Add predictive models where propensity or conversion likelihood is needed.
- Strengthen row-level access and PII controls, and keep testing with authorised mailboxes, before production use.