# Code Style

**Comments and docs describe current state, not history.** Code comments,
test names, and Javadoc should be grounded in what the code does now — not
what it used to do or what bug it fixed. Historicle context belongs in commit
messages and CR descriptions, which are the record of change.

## Examples

Good: `// CoreRegistry is set in initialize() after rootContext is created`
Bad: `// The previous call here passed null`

Good: `@DisplayName("should resolve parent beans")`
Bad: `@DisplayName("before the fix, this was broken")`
