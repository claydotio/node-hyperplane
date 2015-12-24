b = require 'b-assert'
Rx = require 'rx-lite'
zock = require 'zock'
Promise = require 'bluebird'

Hyperplane = require '../src'

API_URL = 'http://hyperplane'
USER_ID = '9fbb8f59-0521-43e8-813e-029ac960865b'
ACCESS_TOKEN = 'TOKEN'

# FIXME: cyclomatic complexity
describe 'emit', ->
  it 'emits events', ->
    callCnt = 0
    cookieSubject = new Rx.BehaviorSubject {}

    zock
    .base API_URL
    .exoid 'auth.login'
    .reply {accessToken: ACCESS_TOKEN}
    .exoid 'users.getMe'
    .reply {id: USER_ID}
    .exoid 'events.create'
    .reply ({body}, {query}) ->
      callCnt += 1
      b body, {app: 'xapp', event: 'EVENT', tags: {x: 'y'}}
      b query, {accessToken: ACCESS_TOKEN}
      b cookieSubject.getValue(), {hyperplaneToken: ACCESS_TOKEN}
      null
    .withOverrides ->
      hp = new Hyperplane
        app: 'xapp'
        api: API_URL + '/exoid'
        cookieSubject: cookieSubject

      hp.emit 'EVENT', {tags: {x: 'y'}}
      .then ->
        hp.emit 'EVENT', {tags: {x: 'y'}}
      .then ->
        b callCnt, 2

  it 'emits event with serverHeaders and defaults, with experimentKey auth', ->
    cookieSubject = new Rx.BehaviorSubject {}

    zock
    .base API_URL
    .exoid 'auth.login'
    .reply ({body}, {query, headers}) ->
      b body,
        app: 'xapp'
        experimentKey: 'abc'
        fields:
          clayId: USER_ID
      b headers['user-agent'], 'Mobile Android'
      {accessToken: ACCESS_TOKEN}
    .exoid 'users.getMe'
    .reply {id: USER_ID}
    .exoid 'events.create'
    .reply ({body}, {query, headers}) ->
      b body,
        app: 'xapp'
        event: 'EVENT'
        tags: {x: 'y'}
        fields:
          clayId: USER_ID
      b headers['user-agent'], 'Mobile Android'
      b query, {accessToken: ACCESS_TOKEN}
      null
    .withOverrides ->
      hp = new Hyperplane
        app: 'xapp'
        api: API_URL + '/exoid'
        cookieSubject: cookieSubject
        serverHeaders: {'user-agent': 'Mobile Android'}
        cache: {}
        experimentKey: Rx.Observable.just 'abc'
        defaults: ->
          Promise.resolve
            fields:
              clayId: USER_ID

      hp.emit 'EVENT', {tags: {x: 'y'}}

  it 'auth with existing token', ->
    cookieSubject = new Rx.BehaviorSubject {hyperplaneToken: 'EXISTING'}

    zock
    .base API_URL
    .exoid 'auth.login'
    .reply ->
      throw new Error 'Not Suppose to call auth.login'
    .exoid 'users.getMe'
    .reply (_, {query}) ->
      b query, {accessToken: 'EXISTING'}
      {id: USER_ID}
    .exoid 'events.create'
    .reply null
    .withOverrides ->
      hp = new Hyperplane
        app: 'xapp'
        api: API_URL + '/exoid'
        cookieSubject: cookieSubject

      hp.emit 'EVENT', {tags: {x: 'y'}}

describe 'getExperiments', ->
  it 'gets experiments', ->
    cookieSubject = new Rx.BehaviorSubject {}

    zock
    .base API_URL
    .exoid 'auth.login'
    .reply {accessToken: ACCESS_TOKEN}
    .exoid 'users.getMe'
    .reply {id: USER_ID}
    .exoid 'users.getExperimentsByApp'
    .reply ({body}) ->
      b body, {app: 'xapp'}
      {abc: 'xyz'}
    .withOverrides ->
      hp = new Hyperplane
        app: 'xapp'
        api: API_URL + '/exoid'
        cookieSubject: cookieSubject

      hp.getExperiments()
      .take(1).toPromise()
      .then (experiments) ->
        b experiments, {abc: 'xyz'}

  it 'gets experiments with experimentKey stream', ->
    cookieSubject = new Rx.BehaviorSubject {}
    experimentKey = new Rx.BehaviorSubject 'xxx'

    zock
    .base API_URL
    .exoid 'auth.login'
    .reply {accessToken: ACCESS_TOKEN}
    .exoid 'users.getMe'
    .reply {id: USER_ID, experimentKey: 'xxx'}
    .exoid 'users.updateMe'
    .reply ({body}) ->
      b body, {experimentKey: experimentKey.getValue()}
      {id: USER_ID, experimentKey: body.experimentKey}
    .exoid 'users.getExperimentsByApp'
    .reply ({body}) ->
      b body, {app: 'xapp', experimentKey: experimentKey.getValue()}
      if experimentKey.getValue() is 'abc'
        {abc: 'xxx'}
      else
        {abc: 'xyz'}
    .withOverrides ->
      hp = new Hyperplane
        app: 'xapp'
        api: API_URL + '/exoid'
        cookieSubject: cookieSubject
        experimentKey: experimentKey

      hp.getExperiments()
      .take(1).toPromise()
      .then (experiments) ->
        b experiments, {abc: 'xyz'}
        experimentKey.onNext 'abc'
      .then ->
        hp.getExperiments()
        .take(1).toPromise()
      .then (experiments) ->
        b experiments, {abc: 'xxx'}

describe 'getCacheStream', ->
  it 'gets exoid cache', ->
    cookieSubject = new Rx.BehaviorSubject {}

    zock
    .base API_URL
    .exoid 'auth.login'
    .reply {accessToken: ACCESS_TOKEN}
    .exoid 'users.getMe'
    .reply {id: USER_ID}
    .exoid 'events.create'
    .reply null
    .withOverrides ->
      hp = new Hyperplane
        app: 'xapp'
        api: API_URL + '/exoid'
        cookieSubject: cookieSubject

      hp.emit 'EVENT', {tags: {x: 'y'}}
      .then ->
        hp.getCacheStream().take(1).toPromise()
        .then (cache) ->
          b Object.keys(cache).length > 0
