Classify the user's request into exactly one route.

Routes:

GENERAL_CHAT
Use when the user is asking a normal question, having a conversation,
asking about capabilities, asking conceptual questions, or when no
specific customer record/profile is supplied for analysis.

CUSTOMER_ANALYSIS
Use when the user provides customer information and wants customer
analysis, targeting, campaign recommendation, engagement, retention,
upsell, or a commercial decision.

Examples:

"Hi, what can you do?"
-> GENERAL_CHAT

"Explain what customer lifetime value means"
-> GENERAL_CHAT

"What campaigns can our system support?"
-> GENERAL_CHAT

"Customer has 8 bookings, high spend and is a repeat customer"
-> CUSTOMER_ANALYSIS

"Should we target this customer?"
-> CUSTOMER_ANALYSIS

Return JSON only:

{
  "route": "GENERAL_CHAT | CUSTOMER_ANALYSIS"
}