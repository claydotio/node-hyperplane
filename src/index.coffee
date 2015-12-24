Rx = require 'rx-lite'
_ = require 'lodash'
Exoid = require 'exoid'
request = require 'clay-request'

AUTH_COOKIE = 'hyperplaneToken'

class Auth
  constructor: ({@exoid, cookieSubject, login}) ->
    initPromise = null
    @waitValidAuthCookie = Rx.Observable.defer =>
      if initPromise?
        return initPromise
      return initPromise = cookieSubject.take(1).toPromise()
      .then (currentCookies) =>
        (if currentCookies[AUTH_COOKIE]?
          @exoid.getCached 'users.getMe'
          .then (user) =>
            if user?
              return {accessToken: currentCookies[AUTH_COOKIE]}
            @exoid.call 'users.getMe'
            .then ->
              return {accessToken: currentCookies[AUTH_COOKIE]}
          .catch ->
            cookieSubject.onNext _.defaults {
              "#{AUTH_COOKIE}": null
            }, currentCookies
            login()
        else
          login())
        .then ({accessToken}) ->
          cookieSubject.onNext _.defaults {
            "#{AUTH_COOKIE}": accessToken
          }, currentCookies

  stream: (path, body) =>
    @waitValidAuthCookie
    .flatMapLatest =>
      @exoid.stream path, body

  call: (path, body) =>
    @waitValidAuthCookie.take(1).toPromise()
    .then =>
      @exoid.call path, body

module.exports = class Hyperplane
  constructor: ({@app, api, cookieSubject, serverHeaders,
    cache, @experimentKey, @defaults}) ->
    serverHeaders ?= {}
    @defaults ?= -> Promise.resolve {}

    accessToken = cookieSubject.map (cookies) ->
      cookies[AUTH_COOKIE]

    proxy = (url, opts) ->
      accessToken.take(1).toPromise()
      .then (accessToken) ->
        proxyHeaders =  _.pick serverHeaders, [
          'cookie'
          'user-agent'
          'accept-language'
          'x-forwarded-for'
        ]
        request url, _.merge {
          qs: if accessToken? then {accessToken} else {}
          headers: _.merge {
            # Avoid CORS preflight
            'Content-Type': 'text/plain'
          }, proxyHeaders
        }, opts

    @exoid = new Exoid
      api: api
      fetch: proxy
      cache: cache

    @auth = new Auth({
      @exoid
      cookieSubject
      login: =>
        Promise.all [
          @defaults()
          @experimentKey?.take(1).toPromise() or Promise.resolve undefined
        ]
        .then ([defaults, experimentKey]) =>
          @exoid.call 'auth.login', _.merge {@app, experimentKey}, defaults
    })

  emit: (event, opts) =>
    @defaults()
    .then (defaults) =>
      body = _.merge _.merge({@app, event}, defaults), opts
      @auth.call 'events.create', body

  getExperiments: =>
    if @experimentKey?
      @experimentKey
      # TODO: ugly - side effect in stream
      .flatMapLatest (experimentKey) =>
        @auth.stream 'users.getMe'
        .take(1).toPromise()
        .then (user) =>
          if user.experimentKey isnt experimentKey
            @auth.call 'users.updateMe', {experimentKey}
        .then ->
          experimentKey
      .flatMapLatest (experimentKey) =>
        @auth.stream 'users.getExperimentsByApp', {@app, experimentKey}
    else
      @auth.stream 'users.getExperimentsByApp', {@app}

  getCacheStream: =>
    @exoid.getCacheStream()
