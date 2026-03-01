using '../main.bicep'

param environmentName = 'dev'
param location = 'eastus2'

// 6-char suffix - change this to something unique to you (your initials + 2 digits)
param uniqueSuffix = 'dev001'

// Your Entra ID Object ID - run this to get it:
// az ad signed-in-user show --query id -o tsv
param adminObjectId = '97b8403f-6953-4de8-a6ea-f3be7a6b9e9b'
