Rx = require 'rx-lite'
_ = require 'lodash'

AUTH_COOKIE = 'hyperplaneToken'

module.exports = class Hyperplane
  constructor: ({@cookieSubject, @app, @apiUrl, @joinEventFn, @proxy}) ->
    @cache = {}

  _auth: =>
    if @cache._auth
      return @cache._auth

    hyperplaneToken = @cookieSubject.getValue()[AUTH_COOKIE]
    joinEventPromise = @joinEventFn()

    # FIXME: should not thow outside a promise
    unless joinEventPromise?.then?
      throw new Error 'joinEventFn must return a promise'

    return joinEventPromise
    .then (joinEvent) =>
      unless _.isPlainObject joinEvent
        throw new Error 'Invalid joinEvent, must be plain object'

      _.merge {@app}, joinEvent
    .then (joinEvent) =>
      @cache._auth = (if hyperplaneToken
        @proxy "#{@apiUrl}/users",
          method: 'POST'
          headers:
            Authorization: "Token #{hyperplaneToken}"
          body: joinEvent
        .catch =>
          @proxy "#{@apiUrl}/users",
            method: 'POST'
            body: joinEvent
      else
        @proxy "#{@apiUrl}/users",
          method: 'POST'
          body: joinEvent
      ).then (user) =>
        cookies = {}
        cookies[AUTH_COOKIE] = user.accessToken
        @cookieSubject.onNext _.defaults cookies, @cookieSubject.getValue()
        return user

  getExperiments: =>
    Rx.Observable.defer =>
      if @cache.experiments
        return @cache.experiments

      return @cache.experiments = @_auth()
      .then (user) =>
        @proxy "#{@apiUrl}/users/me/experiments/#{@app}",
          method: 'GET'
          headers:
            Authorization: "Token #{user.accessToken}"

  emit: (event, opts) =>
    @_auth()
    .then (user) =>
      @proxy "#{@apiUrl}/events/#{event}",
        method: 'POST'
        headers:
          Authorization: "Token #{user.accessToken}"
        body: _.merge {@app}, opts
