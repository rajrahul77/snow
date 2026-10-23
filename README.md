4.2 Use Case 2: Denodo MCP Layer and Multi-Agent Workflow System

Use-Case Description

This use case evaluates how Dataiku agents can work with enterprise customer data exposed through Denodo MCP and coordinate multiple specialised agents within a single user-facing workflow.

The implementation uses the Resort360 customer intelligence dataset. The objective is not only to answer direct analytical questions, but also to support a simple customer-growth workflow in which the system can identify an opportunity, determine the relevant customers, and suggest an appropriate next action.

The solution was deliberately divided into specialised agents to evaluate orchestration, context passing, tool usage, and control between agents. The same business logic could also be implemented through a single LLM call; therefore, the purpose of the multi-agent design is primarily to assess Dataiku's agent orchestration capabilities rather than to establish that a multi-agent architecture is mandatory for this use case.

A general-purpose customer intelligence path was also introduced so that users are not restricted to the predefined growth workflow. Questions such as "Who is the highest-spending customer?" or "Show the top customers by lifetime revenue" can be handled directly using the available customer data.

---

Agents and Responsibilities

Orchestrator Agent

The Orchestrator is the user-facing entry point for the solution. Its responsibility is to understand the type of request and delegate the work to the appropriate specialist agent.

It does not perform customer analysis itself. Instead, it controls which agent should be called, passes the required upstream context to downstream agents, and prevents unrelated agents from being invoked unnecessarily.

For an end-to-end customer-growth request, the expected sequence is:

Portfolio Opportunity Agent → Customer Targeting Agent → Next Best Action Agent.

For a direct customer-data question, the Orchestrator routes the request to the General-Purpose Customer Intelligence Agent instead of running the full workflow.

General-Purpose Customer Intelligence Agent

This agent handles factual and analytical questions that do not require the complete customer-growth workflow.

Typical requests include:

- highest or lowest spending customer;
- top-N customers by revenue;
- booking counts;
- average customer metrics;
- customer-level lookups;
- comparison of customer segments;
- simple filtering and ranking.

The agent uses customer data through the configured data-access tools and is instructed to use structured values as the source of truth rather than relying on generated customer summaries.

Portfolio Opportunity Agent

The Portfolio Opportunity Agent performs portfolio-level analysis and identifies a customer-growth opportunity based on the available customer intelligence data.

Its responsibility is to determine the opportunity, target profile, selection logic, supporting evidence, priority, and business objective.

It does not select individual customers and does not generate a business action. This separation keeps the portfolio-level reasoning independent from customer-level targeting.

Customer Targeting Agent

The Customer Targeting Agent receives the opportunity identified by the Portfolio Opportunity Agent and identifies the actual customers that satisfy the defined targeting criteria.

The upstream opportunity, target profile, selection logic, and objective are treated as fixed inputs. The agent is not expected to redefine the business opportunity.

Customer selection is based on observed data such as booking count, customer segment, revenue, stay duration, and other available structured attributes.

Next Best Action Agent

The Next Best Action Agent receives both the validated portfolio opportunity and the selected customer cohort.

Its role is to convert these upstream outputs into a practical business action.

The agent is deliberately constrained from inventing unsupported information such as customer preferences, discounts, communication channels, expected conversion rates, ROI, or arbitrary campaign targets. Where the available data does not support a specific recommendation, the agent is expected to return a more general action rather than create additional assumptions.

---

Workflow and Agent Interaction

The Orchestrator first classifies the incoming request.

For a customer-growth request, the sequence is:

1. The Portfolio Opportunity Agent analyses the customer portfolio and identifies an opportunity.
2. The Orchestrator checks that the opportunity, target profile, selection logic, and objective are consistent.
3. The complete opportunity output is passed to the Customer Targeting Agent.
4. The Customer Targeting Agent identifies actual customers matching the criteria.
5. The selected customer information and the original opportunity are passed to the Next Best Action Agent.
6. The Next Best Action Agent generates the recommended action and success metric.
7. The Orchestrator presents a single consolidated response to the user.

For a direct analytical question, the Orchestrator bypasses the above sequence and invokes the General-Purpose Customer Intelligence Agent.

This avoids running the full multi-agent chain for simple questions that can be answered directly from the data.

---

Architecture and Data Flow

The high-level architecture consists of four layers:

Data layer:
Customer intelligence data is available through Denodo and is also represented within the Dataiku project.

Tool layer:
Denodo MCP provides controlled access to customer data for agents that require dynamic querying. Dataset-based lookup or SQL-based querying can also be used for deterministic customer-level verification and aggregation.

Agent layer:
Specialised agents perform portfolio analysis, customer targeting, direct analytics, and next-best-action generation.

Orchestration layer:
The Orchestrator coordinates the agents and acts as the single user-facing entry point.

The Orchestrator itself does not require direct Denodo access. Data access remains with the agents responsible for analytical tasks.

---

Tools Exposed Through MCP

Denodo MCP is used to provide agents with controlled access to the Resort360 customer intelligence data.

The MCP layer allows the agents to inspect available data and execute analytical requests without embedding database-specific access logic directly into each agent prompt.

Typical use cases include:

- analysing customer segments;
- comparing customer groups;
- identifying high-value customers;
- retrieving booking and revenue information;
- supporting customer selection criteria.

For deterministic questions such as maximum, minimum, top-N, counts, averages, and rankings, direct dataset or SQL-based access is preferred where appropriate because the result can be derived directly from structured data rather than inferred by the LLM.

---

Agent-to-Agent Context Sharing

Agent outputs are passed explicitly between stages rather than assuming that downstream agents are aware of previous decisions.

For example, the Customer Targeting Agent receives the complete output of the Portfolio Opportunity Agent, including the opportunity, target cohort, selection logic, supporting evidence, and objective.

Similarly, the Next Best Action Agent receives both the portfolio-level result and the customer-targeting result.

This approach reduces ambiguity and makes it easier to trace how a final recommendation was produced.

The downstream agents are instructed not to silently modify key upstream decisions such as the selected cohort or business objective.

---

Error Handling and Recovery

The Orchestrator acts as a control point between agents.

If an agent returns an incomplete or contradictory response, the result should not automatically be passed to the next stage.

The current control rules include:

- retrying a specialist agent when required fields are missing;
- stopping the workflow when no meaningful opportunity can be identified;
- stopping customer-growth processing when no customers satisfy the targeting criteria;
- preventing the Next Best Action Agent from creating an action when there is no valid target cohort;
- treating structured customer data as the source of truth when it conflicts with generated text;
- returning an explicit "insufficient information" response rather than filling missing information with assumptions.

Further retry policies and operational recovery mechanisms would need to be formalised before production deployment.

---

Human Approval Points

No mandatory human approval step is currently enforced in the PoC.

For a production implementation, human approval would be most relevant before an agent-generated recommendation is converted into an external customer action, such as launching a campaign, sending a communication, or applying an offer.

The current implementation therefore stops at recommendation generation and does not directly trigger a customer-facing business action.

---

Security and Governance

The solution separates data access from orchestration.

Only agents that require customer data are given access to the relevant MCP or dataset tools. The Orchestrator mainly coordinates the workflow and does not need direct access to the underlying customer source.

Customer-level structured fields are treated as the source of truth. LLM-generated customer insight fields are used only as supporting context where required.

Personally identifiable information that is not required for analytical reasoning should not be passed between agents.

Agent Hub is used as the user-facing access layer so that the internal specialist agents do not need to be exposed individually to business users.

---

Test Scenarios

The workflow was tested using both end-to-end business questions and direct analytical questions.

Representative scenarios include:

- identify a customer-growth opportunity and recommend the next best action;
- identify actual customers matching an opportunity;
- determine the highest-spending customer;
- return the top customers based on lifetime booking revenue;
- compare repeat and standard customers;
- verify whether selected customers satisfy the upstream targeting criteria;
- test whether the Next Best Action Agent introduces unsupported offers or customer assumptions;
- test whether the Orchestrator chooses the direct analytical path instead of unnecessarily invoking the full workflow.

---

Results and Observations

The PoC demonstrated that Dataiku can coordinate multiple agents while keeping individual responsibilities separated.

Explicit context passing between agents was important. When upstream information was not clearly passed to downstream agents, the downstream response was more likely to become generic or introduce assumptions.

The use of stricter prompts also reduced unsupported statements, particularly in the Next Best Action stage.

A key observation was that not every question benefits from the multi-agent workflow. Simple analytical questions such as rankings, counts, and direct customer lookups are better handled through a general-purpose analytical path.

Another observation was that deterministic structured-data retrieval is preferable for factual customer values. LLM reasoning is more useful for interpreting those values and forming business recommendations than for reproducing data that can be queried directly.

---

Scalability and Operational Considerations

The current implementation is a PoC and is designed primarily to validate orchestration patterns rather than production-scale throughput.

A multi-agent request results in multiple LLM and tool calls, which introduces additional latency and token usage compared with a single-agent implementation.

For this reason, the Orchestrator should invoke only the agents required for a specific request.

Direct analytical questions should avoid the complete multi-agent chain.

At larger scale, additional areas to evaluate include request concurrency, MCP query performance, LLM cost, timeout handling, logging volume, and the number of customer records returned between agents.

---

Risks and Limitations

The primary limitation is that the underlying customer data is largely descriptive. The current system should therefore not present customers as "likely to convert" or "high propensity" unless a predictive model or supporting feature is available.

Agent outputs may also vary between runs because the orchestration still relies on LLM reasoning.

The current multi-agent split adds additional latency and complexity, and some of the workflow could be implemented using a single well-structured LLM call.

The value of the current design is therefore in demonstrating controlled delegation, tool usage, context passing, and governance rather than claiming that multi-agent execution is inherently superior.

The quality of the final recommendation is also limited by the attributes available in the customer intelligence dataset. For example, where channel preference, offer history, campaign response, or recency data is unavailable, the system should not infer those values.

---

Recommended Improvements

The next improvement should be to introduce deterministic verification for customer-level factual values. Customer IDs and key metrics returned by an agent can be validated against the structured customer dataset before being included in the final response.

A SQL-based analytical tool can also be used for aggregation, ranking, top-N, maximum/minimum, and similar questions, while dataset lookup can be used for exact customer-record validation.

Additional improvements include:

- introducing formal output schemas between agents;
- adding automated evaluation scenarios for common user queries;
- monitoring tool-call order and agent traces;
- capturing latency and token consumption per workflow;
- adding human approval before any customer-facing action;
- introducing predictive models where propensity or conversion likelihood is required;
- strengthening row-level access and PII controls before production use.