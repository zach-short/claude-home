<!-- personal-config v0.8.0 · 2026-10-05 · config 2fbe199a · standard v1.2.0 · adapted -->
# Prefer live docs over memory for library APIs

Use Context7 MCP to fetch current documentation whenever the question is about a library, framework,
SDK, API, CLI tool, or cloud service — even well-known ones. This includes API syntax,
configuration, version migration, library-specific debugging, and setup instructions. Use it
even when you think you know the answer: training data may not reflect recent changes. Prefer
it over web search for library docs.

Do not use it for: refactoring, writing scripts from scratch, debugging business logic, code
review, or general programming concepts.

## Steps

1. Resolve the library to an exact identifier the tool understands, unless one was given.
2. Pick the best match by exact name, description relevance, code snippet count, source
   reputation (High or Medium preferred) and benchmark score. With Context7, call
   `resolve-library-id` first unless an exact `/org/project` ID was given, then `query-docs`. If the
   results look wrong, try alternate names or a rephrased query. Use version-specific results
   when a version is named.
3. Query with the full question, not single words, scoped to one concept per call. A question
   spanning several concepts gets one call each — combined queries dilute ranking and return
   shallow results for each topic.
4. Answer from the fetched docs.

**If the tool is not present in this session, say so** and fall back to the installed package's
own README under `node_modules/` or its equivalent. Do not answer from memory silently.
