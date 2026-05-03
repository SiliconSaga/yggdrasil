# Synthetic vault template

Local fixture template used by the ws-hoard-init bats suite. The
`template.yaml` is generated at test setup time so it can point
`upstream:` at a bare git repo created in $BATS_TEST_TMPDIR.
