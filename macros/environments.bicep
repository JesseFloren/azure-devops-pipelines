/*
  Environment macro — maps between full environment names and their shorthands.

  Supported environments:
    Production  → prd
    Acceptance  → acp
    Test        → tst
    Development → dev
*/

@export()
@description('Derive the environment shorthand from the full environment name.')
func getEnvShorthand(environment string) string =>
  environment == 'Production'
    ? 'prd'
    : environment == 'Acceptance'
      ? 'acp'
      : environment == 'Test'
        ? 'tst'
        : 'dev'

@export()
@description('Derive the full environment name from its shorthand.')
func getEnvFullName(envShorthand string) string =>
  envShorthand == 'prd'
    ? 'Production'
    : envShorthand == 'acp'
      ? 'Acceptance'
      : envShorthand == 'tst'
        ? 'Test'
        : 'Development'
