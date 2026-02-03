## Post-change app workflow (mandatory)

After any change in `Sources/TypoFixr/**` or `Tests/TypoFixrTests/**`, before final response:

1. Run: `swift build -c debug`
2. Run: `bash scripts/restart-onboarding.sh`
3. Report build result + restart result in the final response.

Do not skip unless the user explicitly says to skip restart.
If build fails, stop and report the failure.
