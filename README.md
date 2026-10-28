4.2 Use Case 2: Denodo MCP Layer and Multi-Agent Workflow System
Use-Case Description
This use case evaluates how Dataiku agents use Resort360 customer data exposed through Denodo MCP, coordinate specialised agents in one user-facing workflow, and complete that workflow with a human-approved customer email.

The system identifies a growth opportunity, selects relevant customers, recommends a next action and, where required, drafts a personalised email that is sent only after a person approves it. The multi-agent split is used to assess Dataiku's orchestration capabilities, not because the use case requires it.

A general-purpose path also answers direct questions, such as "Who is the highest-spending customer?", without running the full chain.

Agents and Responsibilities
Orchestrator Agent
The user-facing entry point. It classifies each request, delegates to the right agent and passes upstream context downstream. It does not analyse data itself. It is the only component allowed to request the email tool, and it requests one send per recipient.

General-Purpose Customer Intelligence Agent
Answers factual questions such as top-N customers by revenue, booking counts, averages, lookups and segment comparisons, using structured data as the source of truth.

Portfolio Opportunity Agent
Identifies one customer-growth opportunity with its target profile, selection logic, evidence, priority and objective. It does not select customers or define actions.

Customer Targeting Agent
Treats the opportunity as fixed input and returns up to 10 matching customers, each with ID, name, verified email address from the source data and selection rationale. It must not invent email addresses.

Next Best Action Agent
Turns the opportunity and cohort into a practical action and success metric. It must not invent offers, discounts, channels, conversion rates or ROI; concrete offers appear only when approved campaign information supports them.

Email Action (send_email_tool)
A Dataiku Send Message tool using the data-platform-mailer (smtp) channel, with three parameters: recipient, subject and message. It performs no reasoning, and every call passes through human approval.

Workflow
Direct questions go to the General-Purpose agent. A customer-growth request runs as follows:

The Portfolio Opportunity Agent identifies an opportunity, and the Orchestrator checks it for consistency.
The Customer Targeting Agent returns matching customers with verified email addresses.
The Next Best Action Agent returns the action and success metric.
If outreach is requested, the Orchestrator drafts one plain-text email per customer using only verified fields and approved campaign content.
The user reviews the recipient, subject and message and accepts or rejects each email.
Accepted emails are sent once through send_email_tool; rejected emails are not sent.
The Orchestrator records the result per recipient, does not retry automatically, and returns one consolidated response.
If only a recommendation is requested, the workflow ends at step 3.

Architecture and Tools
Data layer: customer data in Denodo, represented in the Dataiku project.
Tool layer: Denodo MCP for dynamic queries; dataset or SQL access for deterministic verification.
Agent layer: specialised analytical and recommendation agents.
Orchestration layer: the Orchestrator as single entry point.
Action layer: send_email_tool, gated by human approval.
Tool

Used by

Purpose

Denodo MCP

Analytical agents

Controlled access to customer, booking and revenue data

Dataset / SQL access

Analytical agents

Deterministic counts, rankings, top-N and record validation

send_email_tool

Orchestrator

Sends one approved email per call

Email Automation
Content and presentation are handled separately. Initially, Markdown markers such as **bold** appeared literally in emails and the body arrived as one dense paragraph.

Content: the Orchestrator writes plain text only, with no Markdown or HTML, in short paragraphs with a greeting and closing.
Presentation: the tool's HTML body template adds a branded header, a 600 px container, readable spacing and a footer, and escapes the message safely.
With this split, emails render correctly. The recipient always comes from the customer's email field in the source data, never from generated text.

Human Approval Points
Human approval is enforced before every email. The interface shows the recipient, subject and full message, and nothing is sent without acceptance. This control stays enabled; removing it would require an explicit change in requirements. Recommendations alone need no approval.

Error Handling and Recovery
Retry an agent when required fields are missing.
Stop when no opportunity or no matching customers are found.
Skip customers without a verified email address.
Treat structured data as the source of truth over generated text.
Return "insufficient information" instead of assumptions.
Make at most one send request per recipient per run, and never retry an uncertain send automatically.
A "call accepted" message does not prove delivery: approval, SMTP acceptance and inbox delivery are checked separately. Failures are investigated through tool output and SMTP logs, which is how an earlier 451 authentication error was resolved.

Security and Governance
Only analytical agents hold data tools, and only the Orchestrator can send email. Generated insight fields never supply a recipient, metric or eligibility. The email step receives only the customer's name, address and approved action. Agent Hub is the user-facing layer, so agents and tools are not exposed directly to business users.

Test Scenarios
Identify an opportunity, target customers and recommend an action.
Answer direct questions such as highest-spending customer and top customers by revenue.
Check that the Next Best Action Agent adds no unsupported offers.
Confirm an email's recipient matches the source data.
Approve one email and confirm correct delivery and formatting; reject one and confirm nothing is sent.
Confirm the email tool is called once per recipient.
Results and Observations
Explicit context passing between agents prevented generic or assumption-based outputs.
Stricter prompts reduced unsupported statements, especially in Next Best Action.
Simple questions are better served by the direct path than the full chain.
End-to-end email delivery was demonstrated after an SMTP authentication issue was fixed.
Separating plain-text content from the HTML template fixed email formatting.
Approval worked as intended before each send.
One early run showed about nine repeated email tool calls; later runs showed one. This needs re-validation.
Scalability and Operational Considerations
This is a PoC. Multi-agent requests add latency and token cost, so the Orchestrator calls only the agents a request needs. The 10-customer cap also limits approval workload. Before scaling, evaluate concurrency, MCP performance, LLM cost, timeouts and mail-provider sending limits.

Risks and Limitations
Data is descriptive, so customers must not be labelled "likely to convert" without a predictive model.
LLM-based orchestration can vary between runs.
Repeated tool calls could send duplicate emails; approval reduces but does not remove this risk.
SMTP acceptance does not guarantee inbox delivery.
Emails may contain incorrect offers if campaign content is not approved.
The chat interface shows chart-style answers as text, because charts need structured tool output.
Recommended Improvements
Validate customer IDs, metrics and email addresses against the dataset before use.
Add a SQL Question Answering tool for rankings and aggregates, which also enables in-chat charts.
Track recipients already emailed per run to prevent duplicates.
Define handling for failed, rejected and uncertain sends.
Source approved campaign content from a governed location.
Add output schemas between agents, automated evaluations and trace monitoring.
Strengthen PII and row-level access controls before production.