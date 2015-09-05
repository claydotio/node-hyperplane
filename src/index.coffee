Rx = require 'rx-lite'
_ = require 'lodash'

AUTH_COOKIE = 'hyperplaneToken'

module.exports = class Hyperplane
  constructor: ({cookieSubject, @app, @apiUrl, @joinEventFn, @proxy}) ->
    initialAuthPromise = null
    @experimentCache = {}

    @accessToken = Rx.Observable.defer =>
      unless initialAuthPromise?
        joinEventPromise = @joinEventFn()

        unless joinEventPromise?.then?
          throw new Error 'joinEventFn must return a promise'

        initialAuthPromise = joinEventPromise
        .then (joinEvent) =>
          unless _.isPlainObject joinEvent
            throw new Error 'Invalid joinEvent, must be plain object'

          _.merge {@app}, joinEvent
        .then (joinEvent) =>
          cookieAccessToken = cookieSubject.getValue()[AUTH_COOKIE]

          (if cookieAccessToken
            @proxy "#{@apiUrl}/users",
              isIdempotent: true
              method: 'POST'
              headers:
                Authorization: "Token #{cookieAccessToken}"
              body: joinEvent
            .catch =>
              @proxy "#{@apiUrl}/users",
                isIdempotent: true
                method: 'POST'
                body: joinEvent
          else
            @proxy "#{@apiUrl}/users",
              isIdempotent: true
              method: 'POST'
              body: joinEvent
          ).then ({accessToken}) -> accessToken
      return initialAuthPromise
    .doOnNext (accessToken) ->
      cookies = {}
      cookies[AUTH_COOKIE] = accessToken
      cookieSubject.onNext _.defaults cookies, cookieSubject.getValue()

  getExperiments: =>
    @accessToken
    .flatMapLatest (accessToken) =>
      cached = @experimentCache[accessToken]
      if cached?
        return cached
      else
        @experimentCache[accessToken] =
          @proxy "#{@apiUrl}/users/me/experiments/#{@app}",
            isIdempotent: true
            method: 'GET'
            headers:
              Authorization: "Token #{accessToken}"

  emit: (event, opts) =>
    @accessToken
    .take(1).toPromise()
    .then (accessToken) =>
      @proxy "#{@apiUrl}/events/#{event}",
        isIdempotent: true
        method: 'POST'
        headers:
          Authorization: "Token #{accessToken}"
        body: _.merge {@app}, opts
