"""
Custom Python agent tool for Dataiku: revenue breakdown with chartable output.

Paste into: GenAI > Agent Tools > New Agent Tool > Custom Python > Design tab.

What it does:
- Runs a SAFE, whitelisted aggregate query (no LLM-written SQL) on dp_customer_intelligence
- Returns a short text answer for the agent
- Returns the rows as a RECORDS artifact in "sources" so the chat UI can build a chart

BEFORE RUNNING: edit the CONFIG block below to match your real column names
(Dataset > Schema tab).
"""

import logging
import dataiku
from dataiku import SQLExecutor2
from dataiku.llm.agent_tools import BaseAgentTool

# ----------------------------- CONFIG ---------------------------------------
DATASET_NAME = "dp_customer_intelligence"

# Columns the agent is allowed to group by: {label shown to LLM: real SQL column}
GROUP_BY_COLUMNS = {
    "nationality": "customer_nationality",   # <-- check exact column name
    # "segment": "customer_segment",
    # "country": "country",
}

# Metrics the agent is allowed to compute: {label: SQL expression}
METRICS = {
    "total_revenue": 'SUM("total_revenue")',  # <-- check exact column name
    "customer_count": "COUNT(*)",
    # "avg_revenue": 'AVG("total_revenue")',
}

MAX_ROWS = 25
# ---------------------------------------------------------------------------


class RevenueBreakdownTool(BaseAgentTool):

    def set_config(self, config, plugin_config):
        self.logger = logging.getLogger(__name__)
        self.config = config

    def get_descriptor(self, tool):
        return {
            "description": (
                "Aggregates Resort360 customer data and returns a ranked table "
                "(e.g. total revenue by nationality). Use this for any question "
                "asking for totals, counts, rankings, shares or charts by a category."
            ),
            "inputSchema": {
                "title": "Revenue breakdown input",
                "type": "object",
                "properties": {
                    "group_by": {
                        "type": "string",
                        "enum": list(GROUP_BY_COLUMNS.keys()),
                        "description": "Category to group by.",
                    },
                    "metric": {
                        "type": "string",
                        "enum": list(METRICS.keys()),
                        "description": "Metric to compute per group.",
                    },
                    "top_n": {
                        "type": "integer",
                        "description": f"Number of top groups to return (1-{MAX_ROWS}). Default 10.",
                    },
                },
                "required": ["group_by", "metric"],
            },
        }

    def invoke(self, input, trace):
        args = input.get("input", {})
        group_label = args.get("group_by")
        metric_label = args.get("metric")
        top_n = args.get("top_n") or 10

        # Validate against whitelists (never trust free text in SQL)
        if group_label not in GROUP_BY_COLUMNS or metric_label not in METRICS:
            return {"output": f"Unsupported request. group_by must be one of "
                              f"{list(GROUP_BY_COLUMNS)}, metric one of {list(METRICS)}."}
        try:
            top_n = max(1, min(int(top_n), MAX_ROWS))
        except (TypeError, ValueError):
            top_n = 10

        group_col = GROUP_BY_COLUMNS[group_label]
        metric_expr = METRICS[metric_label]

        dataset = dataiku.Dataset(DATASET_NAME)
        table = dataset.get_location_info().get("info", {}).get("quotedResolvedTableName")
        executor = SQLExecutor2(dataset=dataset)

        query = f'''
            SELECT "{group_col}" AS "{group_label}",
                   ROUND(CAST({metric_expr} AS NUMERIC), 2) AS "{metric_label}"
            FROM {table}
            WHERE "{group_col}" IS NOT NULL
            GROUP BY "{group_col}"
            ORDER BY 2 DESC
            LIMIT {top_n}
        '''
        self.logger.info(query)

        df = executor.query_to_df(query)
        if df.empty:
            return {"output": "The query returned no rows."}

        columns = df.columns.tolist()
        data = [[r[0], float(r[1])] for r in df.values.tolist()]

        # Short text summary for the agent (no invented numbers - all from SQL)
        lines = [f"{g}: {v:,.2f}" for g, v in data]
        output = (f"Top {len(data)} {group_label} by {metric_label}:\n" + "\n".join(lines))

        return {
            "output": output,
            "sources": [
                {
                    "toolCallDescription": f"{metric_label} by {group_label}",
                    "items": [
                        {"type": "GENERATED_SQL_QUERY", "performedQuery": query.strip()},
                        {"type": "RECORDS", "records": {"columns": columns, "data": data}},
                    ],
                }
            ],
        }
