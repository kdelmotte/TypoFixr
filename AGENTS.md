## Post-change app workflow (mandatory)

After any change in `Sources/TypoFixr/**` or `Tests/TypoFixrTests/**`, before final response:

1. Run: `make build`
2. Run: `make deploy`
3. Report build result + deploy result in the final response.

Do not skip unless the user explicitly says to skip deploy.
If build fails, stop and report the failure.
