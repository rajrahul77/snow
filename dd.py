# Resort360 Data Explorer - Dataiku Dash webapp
# Paste this whole file into: Code > Webapps > New webapp > Code webapp > Dash > Python tab.
#
# Flow: user picks a table -> clicks "Lock table" -> asks questions.
# The LLM writes ONE query; this code checks it only reads the locked table,
# runs it on Denodo, then shows a chart + table + the query used.

import io
import json
import re

import dataiku
import pandas as pd
import plotly.express as px
from dash import Input, Output, State, dash_table, dcc, html
from dataiku import SQLExecutor2

# ---------------- CONFIG (edit these) ----------------
CONNECTION = "Denodo_Resort360_Postgres"   # existing Denodo connection (the one that worked in the notebook)
DATABASE = "resort360_n"                   # Denodo database holding the views
LLM_ID = "PASTE_LLM_ID_HERE"               # see setup step 2 (use a Gemini Flash id)
ALLOWED_TABLES = []                        # e.g. ["dp_customer_intelligence", "bookings"]; empty = read list from Denodo
MAX_ROWS = 50
IMPERSONATE = False                        # True only after webapp impersonation (RBAC) is set up
# ------------------------------------------------------

BLOCKED = re.compile(
    r"\b(insert|update|delete|drop|create|alter|truncate|merge|grant|revoke)\b", re.I)
TABLE_REF = re.compile(
    r'\b(?:from|join)\s+((?:"[^"]+"|\w+)(?:\s*\.\s*(?:"[^"]+"|\w+))?)', re.I)
PII_WORDS = ["first name", "last name", "full name", "email", "mobile",
             "phone", "address", "passport", "birth"]


# ---------- data helpers ----------
def run_sql(sql):
    """Run a query on Denodo, as the end user if impersonation is enabled."""
    if IMPERSONATE:
        with dataiku.WebappImpersonationContext():
            return SQLExecutor2(connection=CONNECTION).query_to_df(sql)
    return SQLExecutor2(connection=CONNECTION).query_to_df(sql)


def list_tables():
    if ALLOWED_TABLES:
        return sorted(ALLOWED_TABLES)
    df = run_sql(f"SELECT name FROM GET_VIEWS() WHERE database_name = '{DATABASE}'")
    return sorted(df.iloc[:, 0].astype(str).tolist())


def is_pii(col):
    return any(w in str(col).lower() for w in PII_WORDS)


def table_profile(table):
    df = run_sql(f'SELECT * FROM "{DATABASE}"."{table}" LIMIT 3')
    cols = [c for c in df.columns if not is_pii(c)]
    sample = json.loads(df[cols].to_json(orient="records", date_format="iso"))
    return cols, sample


# ---------- LLM + safety ----------
def ask_llm_for_sql(table, cols, sample, question):
    prompt = f"""You write ONE read-only Denodo VQL SELECT query.
Table: "{DATABASE}"."{table}" (use exactly this name; never use any other table).
Columns you may use: {", ".join(f'"{c}"' for c in cols)}
Sample rows: {json.dumps(sample)[:2000]}
Rules:
- Use only the columns above, always in double quotes.
- For counts, totals or averages, aggregate with GROUP BY one or two category columns.
- Return at most 20 rows, ordered by the main number, highest first.
- Never break down by gender or nationality.
Return ONLY the query. No explanation.
Question: {question}"""
    llm = dataiku.api_client().get_default_project().get_llm(LLM_ID)
    completion = llm.new_completion()
    completion.with_message(prompt)
    text = completion.execute().text or ""
    match = re.search(r"```(?:sql|vql)?\s*(.*?)```", text, re.S | re.I)
    return (match.group(1) if match else text).strip().rstrip(";")


def check_sql(sql, table):
    """Return an error message if the query is not allowed, else None."""
    if not sql.lower().startswith(("select", "with")) or ";" in sql or BLOCKED.search(sql):
        return "Blocked: only one read-only SELECT is allowed."
    refs = [r.split(".")[-1].strip().strip('"').lower() for r in TABLE_REF.findall(sql)]
    if not refs or any(r != table.lower() for r in refs):
        return f"Blocked: this session is locked to '{table}'."
    return None


def make_chart(df):
    if df.empty or len(df.columns) < 2:
        return None
    nums = df.select_dtypes("number").columns.tolist()
    cats = [c for c in df.columns if c not in nums]
    if nums and cats:
        return px.bar(df, x=cats[0], y=nums[0])
    if len(nums) >= 2:
        return px.scatter(df, x=nums[0], y=nums[1])
    return None


# ---------- layout ----------
def serve_layout():
    try:
        options = [{"label": t, "value": t} for t in list_tables()]
        note = ""
    except Exception as e:
        options, note = [], f"Could not load tables: {e}"
    return html.Div(
        style={"maxWidth": "1000px", "margin": "24px auto", "fontFamily": "sans-serif"},
        children=[
            html.H2("Resort360 Data Explorer"),
            html.P(note, style={"color": "crimson"}),
            html.Div(style={"display": "flex", "gap": "8px"}, children=[
                html.Div(dcc.Dropdown(id="table", options=options,
                                      placeholder="1. Choose a table"), style={"flex": 1}),
                html.Button("Lock table", id="lock"),
            ]),
            html.P(id="locked", style={"fontWeight": "bold"}),
            dcc.Store(id="session"),
            dcc.Textarea(id="question", placeholder="2. Ask a question about this table",
                         style={"width": "100%", "height": "70px", "marginTop": "8px"}),
            html.Button("Ask", id="ask", style={"marginTop": "8px"}),
            dcc.Loading(html.Div(id="result", style={"marginTop": "16px"})),
        ],
    )


app.layout = serve_layout  # noqa: F821  (`app` is provided by Dataiku)


# ---------- callbacks ----------
@app.callback(  # noqa: F821
    Output("session", "data"), Output("locked", "children"), Output("table", "disabled"),
    Input("lock", "n_clicks"), State("table", "value"), prevent_initial_call=True)
def lock_table(_, table):
    if not table:
        return None, "Choose a table first.", False
    try:
        cols, sample = table_profile(table)
    except Exception as e:
        return None, f"Could not read {table}: {e}", False
    return ({"table": table, "cols": cols, "sample": sample},
            f"Locked to {table}. Reload the page to switch tables.", True)


@app.callback(  # noqa: F821
    Output("result", "children"),
    Input("ask", "n_clicks"), State("question", "value"), State("session", "data"),
    prevent_initial_call=True)
def ask(_, question, session):
    if not session:
        return "Lock a table first."
    if not question:
        return "Type a question."
    table = session["table"]

    sql = ask_llm_for_sql(table, session["cols"], session["sample"], question)
    error = check_sql(sql, table)
    if error:
        return html.Div([html.P(error), html.Pre(sql)])

    try:
        df = run_sql(sql).head(MAX_ROWS)
    except Exception as e:
        return html.Div([html.P(f"Query failed: {e}"), html.Pre(sql)])

    df = df[[c for c in df.columns if not is_pii(c)]]          # never show personal data
    records = json.loads(df.to_json(orient="records", date_format="iso"))
    fig = make_chart(pd.read_json(io.StringIO(json.dumps(records))))

    return html.Div([
        dcc.Graph(figure=fig) if fig is not None else html.Div(),
        dash_table.DataTable(data=records,
                             columns=[{"name": str(c), "id": str(c)} for c in df.columns],
                             page_size=10),
        html.Details([html.Summary("Query used"), html.Pre(sql)]),
    ])
