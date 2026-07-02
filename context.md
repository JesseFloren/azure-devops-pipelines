### Rules
You must follow these rules when generating infra as code

- Always in Bicep
- Use AVM always when possible (Azure Validated Modules)
- Private connectivity where possible
- All subnets have limited NSGs. By default allow vnet inbound and outbound, and add required rules for the functionality of the request.
- All deployments should conform to the Cloud Adoption Framework
- All deployments should conform to the Platform landing zone.
- Naming convention according to Azure Naming Tool resources: "{appShorthand: 3-5 letters}-{env: dev|tst|acp|prd}-{rgShorthand: pfu|app|custom if not in application landing zone}-{resourceShorthand: appi|st|mdp|rg|etc. (from naming tool)}{instance: 001|002}"
- Cannot contain role assignments
- Requires md file of manual steps (role assignments, app registrations etc.)
- SKU is always variable where possible
- Naming should always be editable in a config if needed, this can be bicep or bicepparam
- Work with the following structure: main.bicep, main.bicepparam, modules, resources, macros
- modules contain modules if required to port over from AVM in the modules/avm folder
- Custom modules are in the root of the modules folder.
- resources contain seperate bicep files per resource group, with naming convention {rgShorthand}-resources.bicep
- Every resource should have the proper tags as defined in CAF, but never the shorhands. (appShorthand and envShorthand should be the full names and added as tags: Environment: Production, Application: DBC-Informatie-Systeem as an example instead of prd and dis)
- Never require multiple params if they can be standard defined from another one: never ask for envShorthand and Environment, as Environment is always Production, Acceptance, Test or Development, and the shorthand is then automatically prd, acp, tst, dev.
- Make functions for anything like naming or environments that can be reused in other projects. Store these in macros.
- All resources should come from a module. This can be AVM or a custom module is made.


### Request Rules
When violated request it to be added to the conversation before continueing

- Request must require resource groups that are to be made, with shortHand.
- If request is subscription or resource group scope.
- It cannot contain role assignments or app registrations.
- Shorthand for the app is provided as well as full name
- The context for the addition or creation needs to be provided. What is my goal with these resources and why do i need them. Actively advise if what they are requesting does not benefit their goal.

