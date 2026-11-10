# run_vql_for_chart - Dataiku Custom Python agent tool
# GenAI > Agent Tools > New agent tool > Custom Python > paste this file.
#
# Re-runs the VQL the agent already wrote and returns the result as
# structured records, so Agent Hub can draw a chart from it.

import json
import re

from dataiku import SQLExecutor2
from dataiku.llm.agent_tools import BaseAgentTool

CONNECTION = "Denodo_Resort360_Postgres"   # same connection that worked in the webapp
MAX_ROWS = 50

BLOCKED = re.compile(
    r"\b(insert|update|delete|drop|create|alter|truncate|merge|grant|revoke)\b", re.I)
PII_WORDS = ["first name", "last name", "full name", "email", "mobile",
             "phone", "address", "passport", "birth"]


def _clean(vql):
    vql = (vql or "").strip()
    fenced = re.search(r"```(?:sql|vql)?\s*(.*?)```", vql, re.S | re.I)
    return (fenced.group(1) if fenced else vql).strip().rstrip(";")


class RunVqlForChart(BaseAgentTool):
    def set_config(self, config, plugin_config):
        self.config = config

    def get_descriptor(self, tool):
        return {
            "description": (
                "Runs ONE read-only VQL SELECT you already wrote and returns the result "
                "as structured rows so the chat can show a chart. Call it after any count, "
                "total, average, top-N or breakdown query, with the SAME VQL. Max 50 rows."
            ),
            "inputSchema": {
                "$id": "https://resort360/tools/run_vql_for_chart",
                "title": "run_vql_for_chart input",
                "type": "object",
                "properties": {
                    "vql": {"type": "string",
                            "description": "One grouped SELECT statement"},
                    "title": {"type": "string",
                              "description": "Short chart title"},
                },
                "required": ["vql"],
            },
        }

    def invoke(self, input, trace):
        args = input.get("input", {})
        vql = _clean(args.get("vql"))

        # Safety: one read-only SELECT only
        if (not vql.lower().startswith(("select", "with"))
                or ";" in vql or BLOCKED.search(vql)):
            return {"output": "Rejected: only a single read-only SELECT is allowed."}

        try:
            df = SQLExecutor2(connection=CONNECTION).query_to_df(vql).head(MAX_ROWS)
        except Exception as e:
            return {"output": f"Query failed: {e}"}

        df = df[[c for c in df.columns if not any(w in str(c).lower() for w in PII_WORDS)]]
        rows = json.loads(df.to_json(orient="values", date_format="iso"))
        columns = [str(c) for c in df.columns]

        return {
            # What the agent reads
            "output": df.to_csv(index=False),
            # What Agent Hub uses for "See details > Sources" and charts
            "sources": [{
                "toolCallDescription": args.get("title") or "Resort360 data",
                "items": [
                    {"type": "GENERATED_SQL_QUERY", "performedQuery": vql},
                    {"type": "RECORDS",
                     "records": {"columns": columns, "data": rows}},
                ],
            }],
        }
