request = require 'clay-request'

AUTH_COOKIE = 'hyperplaneToken'
COOKIE_DURATION_MS = 365 * 24 * 3600 * 1000 # 1 year

b64encode = (str) ->
  if window?
    window.btoa str
  else
    new Buffer(str).toString('base64')


module.exports = class Hyperplane
  constructor: ({@apiUrl, @namespace, @cookies, @domain, @setCookie}) ->
    @cache = {}

  _auth: =>
    if @cache._auth
      return @cache._auth

    hyperplaneToken = @cookies[AUTH_COOKIE]
    @cache._auth = (if hyperplaneToken
      request "#{@apiUrl}/users",
        method: 'POST'
        headers:
          Authorization: "Basic #{b64encode(hyperplaneToken)}"
      .catch =>
        request "#{@apiUrl}/users",
          method: 'POST'
    else
      request "#{@apiUrl}/users",
        method: 'POST'
    ).then (user) =>
      @setCookie AUTH_COOKIE, user.accessToken, {
        path: '/'
        domain: @domain
        expires: new Date(Date.now() + COOKIE_DURATION_MS)
      }
      return user

    return @cache._auth

  getExperiments: =>
    if @cache.experiments
      return @cache.experiments

    @cache.experiments = @_auth()
    .then (user) =>
      request "#{@apiUrl}/experiments/#{@namespace}",
        headers:
          Authorization: "Basic #{b64encode(user.accessToken)}"
