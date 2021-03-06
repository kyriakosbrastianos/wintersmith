
path = require 'path'
async = require 'async'
{logger, readJSON} = require '../common'

exports.commonOptions = defaults =
  config:
    alias: 'c'
    default: './config.json'
  contents:
    alias: 'i'
    default: './contents'
  templates:
    alias: 't'
    default: './templates'
  locals:
    alias: 'L'
    default: {}
  chdir:
    alias: 'C'
    default: null
  plugins:
    alias: 'P'
    default: []

exports.commonUsage = [
  "-C, --chdir [path]            change the working directory"
  "  -c, --config [path]           path to config (defaults to #{ defaults.config.default })"
  "  -i, --contents [path]         contents location (defaults to #{ defaults.contents.default })"
  "  -t, --templates [path]        template location (defaults to #{ defaults.templates.default })"
  "  -L, --locals [path]           optional path to json file containing template context data"
  "  -P, --plugins                 comma separated list of modules to load as plugins"
].join '\n'

exports.getOptions = (argv, callback) ->
  ### resolves options with the hierarchy: argv > configfile > defaults
      returns a options object ###

  workDir = path.resolve (argv.chdir or process.cwd())
  logger.verbose "resolving options - work directory: #{ workDir }"

  async.waterfall [
    (callback) ->
      # load config if present
      configPath = path.join workDir, argv.config
      path.exists configPath, (exists) ->
        if exists
          logger.info "using config file: #{ configPath }"
          readJSON configPath, callback
        else
          logger.verbose "no config file found"
          callback null, {}
    (options, callback) ->
      logger.verbose 'options:', options
      for key of defaults
        # assing defaults to missing conf options
        options[key] ?= defaults[key].default
        # ovveride conf and default options with any command line options
        if argv[key]? and argv[key] != defaults[key].default
          options[key] = argv[key]
      # pass along extra arguments from argv
      for key of argv
        # don't include optimist stuff
        if key[0] == '_' or key[0] == '$'
          continue
        options[key] ?= argv[key]
      # expand paths
      for key in ['output', 'config', 'contents', 'templates']
        if options[key]
          options[key] = path.resolve workDir, options[key]
      callback null, options
    (options, callback) ->
      # load locals json if neccessary
      if typeof options.locals == 'string'
        filename = path.join workDir, options.locals
        logger.verbose "loading locals from: #{ filename }"
        readJSON filename, (error, result) ->
          if error
            callback error
          else
            options.locals = result
            callback null, options
      else
        callback null, options
    (options, callback) ->
      if typeof options.plugins is 'string'
        options.plugins = options.plugins.split ','
      # resolve plugin paths if required as file
      async.map options.plugins, (item, callback) ->
        if item[...2] is './'
          item = path.resolve workDir, item
        callback null, item
      , (error, result) ->
        options.plugins = result
        callback error, options
    (options, callback) ->
      logger.verbose 'resolved options:', options
      logger.verbose 'validating paths'
      paths = ['contents', 'templates']
      async.forEach paths, (filepath, callback) ->
        path.exists options[filepath], (exists) ->
          if exists
            callback()
          else
            callback new Error "#{ filepath } path invalid (#{ options[filepath] })"
      , (error) ->
        callback error, options
  ], callback

exports.loadPlugins = (plugins, callback) ->
  wintersmith = require './../'
  async.forEach plugins, (plugin, callback) ->
    logger.verbose "loading plugin: #{ plugin }"
    try
      module = require plugin
    catch error
      return callback error
    module wintersmith, callback
  , callback
