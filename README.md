import json
import re
from dataiku import SQLExecutor2
from dataiku.llm.agent_tools import BaseAgentTool

CONNECTION = "Denodo_Resort360"   # existing Denodo connection
MAX_ROWS = 50
BLOCKED = re.compile(
    r"\b(insert|update|delete|drop|create|alter|truncate|merge|grant|revoke)\b", re.I)


class RunVqlForChart(BaseAgentTool):
    def set_config(self, config, plugin_config):
        self.config = config

    def get_descriptor(self, tool):
        return {
            "description": (
                "Runs ONE read-only VQL SELECT you already wrote and returns the result "
                "as a table the chat can turn into a chart. Use after any count, total, "
                "average or breakdown query. Max 50 rows."
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
        args = input["input"]
        vql = args["vql"].strip().rstrip(";")

        # Safety: one read-only SELECT only
        if (not vql.lower().startswith(("select", "with"))
                or ";" in vql or BLOCKED.search(vql)):
            return {"output": "Rejected: only a single read-only SELECT is allowed."}

        df = SQLExecutor2(connection=CONNECTION).query_to_df(vql).head(MAX_ROWS)
        rows = json.loads(df.to_json(orient="values", date_format="iso"))

        return {
            "output": df.to_csv(index=False),          # what the agent reads
            "sources": [{                               # what Agent Hub charts
                "toolCallDescription": args.get("title", "Resort360 data"),
                "items": [
                    {"type": "GENERATED_SQL_QUERY", "performedQuery": vql},
                    {"type": "RECORDS",
                     "records": {"columns": [str(c) for c in df.columns],
                                 "data": rows}},
                ],
            }],
        }