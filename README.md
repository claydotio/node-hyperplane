# node-hyperplane

```coffee
@hyperplane = new Hyperplane
  app: config.HYPERPLANE_APP
  api: config.HYPERPLANE_API_URL + '/exoid'
  cookieSubject: cookieSubject
  serverHeaders: serverHeaders
  cache: cache.hyperplane
  experimentKey: @user.getMe().map ({id}) -> id
  defaults: =>
    @user.getMe().take(1).toPromise()
    .then ({id}) ->
      fields:
        clayId: id
```
