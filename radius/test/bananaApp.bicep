extension radius
resource environment 'Applications.Core/environments@2023-10-01-preview' = {
  name: 'banana-env'
  properties: {
    compute: {
      kind: 'kubernetes'
      namespace: 'banana-env'
    }
  }
}

// The Radius application definition.
resource application 'Applications.Core/applications@2023-10-01-preview' = {
  name: 'banana-app'
  properties: {
    environment: environment.id
  }
}

module container 'modules/democontainer.bicep' = {
  name: 'banana-container'
  params: {
    application: application.id
    containerName: 'banana-app-container'
  }
}
