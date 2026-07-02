/*
  Naming macro — CAF naming convention helper.

  Convention: {appShorthand}-{envShorthand}-{rgShorthand}-{resourceShorthand}{instance}
  Example   : man-prd-devops-rg001
*/

@export()
@description('Generate a resource name following the CAF naming convention.')
func getName(
  appShorthand string,
  envShorthand string,
  rgShorthand string,
  resourceShorthand string,
  instance string
) string => '${appShorthand}-${envShorthand}-${rgShorthand}-${resourceShorthand}${instance}'

@export()
@description('Generate a lowercase storage account name following the CAF naming convention without hyphens.')
func getStorageAccountName(
  appShorthand string,
  envShorthand string,
  rgShorthand string,
  resourceShorthand string,
  instance string
) string => toLower('${appShorthand}${envShorthand}${rgShorthand}${resourceShorthand}${instance}')
