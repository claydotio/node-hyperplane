assert = require 'assert'
Rx = require 'rx-lite'
zock = require 'zock'

Promise = require 'bluebird'

Hyperplane = require '../src'

# FIXME: cyclomatic complexity
describe 'emit', ->
  it 'emits events', ->
    eventAssert = false
    app = 'testapp'
    apiUrl = 'http://test'
    cookieSubject = new Rx.BehaviorSubject {}
    joinEventFn = ->
      Promise.resolve {}
    proxy = (path, opts) ->
      switch path
        when "#{apiUrl}/users"
          Promise.resolve {accessToken: 'ACCESS_TOKEN'}
        when "#{apiUrl}/events/EVENT"
          eventAssert = true
          assert.deepEqual opts.body, {app}
          assert.deepEqual opts.headers, Authorization: 'Token ACCESS_TOKEN'
          Promise.resolve null

    hp = new Hyperplane({cookieSubject, app, apiUrl, joinEventFn, proxy})
    hp.emit 'EVENT'
    .then ->
      assert eventAssert

  it 'does not auth twice', ->
    authCount = 0
    app = 'testapp'
    apiUrl = 'http://test'
    cookieSubject = new Rx.BehaviorSubject {}
    joinEventFn = ->
      Promise.resolve {}
    proxy = (path, opts) ->
      switch path
        when "#{apiUrl}/users"
          authCount += 1
          Promise.resolve {}
        when "#{apiUrl}/events/EVENT"
          Promise.resolve null

    hp = new Hyperplane({cookieSubject, app, apiUrl, joinEventFn, proxy})
    hp.emit 'EVENT'
    .then ->
      hp.emit 'EVENT'
    .then ->
      assert.equal authCount, 1

  it 'auth with existing token', ->
    assertAuth = false
    app = 'testapp'
    apiUrl = 'http://test'
    cookieSubject = new Rx.BehaviorSubject {hyperplaneToken: 'ACCESS_TOKEN'}
    joinEventFn = ->
      Promise.resolve {}
    proxy = (path, opts) ->
      switch path
        when "#{apiUrl}/users"
          assertAuth = true
          assert.equal opts.headers.Authorization, 'Token ACCESS_TOKEN'
          Promise.resolve {}
        when "#{apiUrl}/events/EVENT"
          Promise.resolve null

    hp = new Hyperplane({cookieSubject, app, apiUrl, joinEventFn, proxy})
    hp.emit 'EVENT'
    .then ->
      assert assertAuth

  it 're-auths when existing token errors', ->
    authCount = 0
    app = 'testapp'
    apiUrl = 'http://test'
    cookieSubject = new Rx.BehaviorSubject {hyperplaneToken: 'INVALID'}
    joinEventFn = ->
      Promise.resolve {}
    proxy = (path, opts) ->
      switch path
        when "#{apiUrl}/users"
          authCount += 1
          if opts.headers?.Authorization is 'Token INVALID'
            Promise.reject new Error '401'
          else
            Promise.resolve {accessToken: 'VALID'}
        when "#{apiUrl}/events/EVENT"
          Promise.resolve null

    hp = new Hyperplane({cookieSubject, app, apiUrl, joinEventFn, proxy})
    hp.emit 'EVENT'
    .then ->
      assert.equal authCount, 2

  it 'emits events with custom data', ->
    eventAssert = false
    app = 'testapp'
    apiUrl = 'http://test'
    cookieSubject = new Rx.BehaviorSubject {}
    joinEventFn = ->
      Promise.resolve {}
    proxy = (path, opts) ->
      switch path
        when "#{apiUrl}/users"
          Promise.resolve {}
        when "#{apiUrl}/events/EVENT"
          eventAssert = true
          assert.deepEqual opts.body,
            app: app
            tags:
              x: 'xxx'
          Promise.resolve null

    hp = new Hyperplane({cookieSubject, app, apiUrl, joinEventFn, proxy})
    hp.emit 'EVENT', {tags: {x: 'xxx'}}
    .then ->
      assert eventAssert

  it 'creates user with data when emitting first event, setting cookie', ->
    userAssert = false
    app = 'testapp'
    apiUrl = 'http://test'
    cookieSubject = new Rx.BehaviorSubject {}
    joinEventFn = ->
      Promise.resolve
        tags:
          x: 'xxx'
        fields:
          y: 'yyy'
    proxy = (path, opts) ->
      switch path
        when "#{apiUrl}/users"
          userAssert = true
          assert.deepEqual opts.body,
            app: app
            tags:
              x: 'xxx'
            fields:
              y: 'yyy'
          Promise.resolve {accessToken: 'ACCESS_TOKEN'}
        when "#{apiUrl}/events/EVENT"
          Promise.resolve null

    hp = new Hyperplane({cookieSubject, app, apiUrl, joinEventFn, proxy})
    hp.emit 'EVENT'
    .then ->
      assert userAssert
      assert.equal cookieSubject.getValue().hyperplaneToken, 'ACCESS_TOKEN'

  it 'requires joinEventFn to return a promise', ->
    app = 'testapp'
    apiUrl = 'http://test'
    cookieSubject = new Rx.BehaviorSubject {}
    joinEventFn = ->
      null
    proxy = -> null

    hp = new Hyperplane({cookieSubject, app, apiUrl, joinEventFn, proxy})
    try
      hp.emit 'EVENT'
    catch err
      assert.equal err.message, 'joinEventFn must return a promise'

  it 'requires joinEventFn to resolve to a plain object', ->
    app = 'testapp'
    apiUrl = 'http://test'
    cookieSubject = new Rx.BehaviorSubject {}
    joinEventFn = ->
      Promise.resolve null
    proxy = -> null

    hp = new Hyperplane({cookieSubject, app, apiUrl, joinEventFn, proxy})
    hp.emit 'EVENT'
    .catch (err) ->
      assert.equal err.message, 'Invalid joinEvent, must be plain object'

describe 'getExperiments', ->
  it 'gets experiments', ->
    experimentAssert = false
    app = 'testapp'
    apiUrl = 'http://test'
    cookieSubject = new Rx.BehaviorSubject {}
    joinEventFn = ->
      Promise.resolve {}
    proxy = (path, opts) ->
      switch path
        when "#{apiUrl}/users"
          Promise.resolve {}
        when "#{apiUrl}/users/me/experiments/#{app}"
          experimentAssert = true
          Promise.resolve {
            test: 'a'
          }

    hp = new Hyperplane({cookieSubject, app, apiUrl, joinEventFn, proxy})
    hp.getExperiments()
    .take(1).toPromise()
    .then (experiments) ->
      assert.equal experiments.test, 'a'
      assert experimentAssert

  it 'caches experiments', ->
    experimentCount = 0
    app = 'testapp'
    apiUrl = 'http://test'
    cookieSubject = new Rx.BehaviorSubject {}
    joinEventFn = ->
      Promise.resolve {}
    proxy = (path, opts) ->
      switch path
        when "#{apiUrl}/users"
          Promise.resolve {}
        when "#{apiUrl}/users/me/experiments/#{app}"
          experimentCount += 1
          Promise.resolve null

    hp = new Hyperplane({cookieSubject, app, apiUrl, joinEventFn, proxy})
    hp.getExperiments()
    .take(1).toPromise()
    .then ->
      assert.equal experimentCount, 1
    .then ->
      hp.getExperiments()
      .take(1).toPromise()
    .then ->
      assert.equal experimentCount, 1
