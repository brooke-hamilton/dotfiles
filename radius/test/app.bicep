extension radius

param environment string
param appName string = 'todoapp'
param containerName string = 'todocontainer'

resource application 'Applications.Core/applications@2023-10-01-preview' = {
  name: appName
  properties: {
    environment: environment
  }
}

resource demo 'Applications.Core/containers@2023-10-01-preview' = {
  name: containerName
  properties: {
    application: application.id
    environment: environment
    container: {
      image: 'ghcr.io/radius-project/samples/demo:latest'
      ports: {
        web: {
          containerPort: 3000
        }
      }
    }
  }
}
