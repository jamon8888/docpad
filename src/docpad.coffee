# =====================================
# Requires

# Necessary
pathUtil = require('path')
fsUtil = require('fs')
_ = require('underscore')
caterpillar = require('caterpillar')
queryEngine = require('query-engine')
CSON = require('cson')
balUtil = require('bal-util')
EventSystem = balUtil.EventSystem
airbrake = null

# Local
PluginLoader = require(__dirname+'/plugin-loader')
BasePlugin = require(__dirname+'/plugin')
Base = require(__dirname+'/base')
FileModel = require(__dirname+'/models/file')
DocumentModel = require(__dirname+'/models/document')
QueryCollection = require(__dirname+'/base').QueryCollection
ElementsCollection = require(__dirname+'/collections/elements')
ScriptsCollection = require(__dirname+'/collections/scripts')
StylesCollection = require(__dirname+'/collections/styles')
require(__dirname+'/prototypes')


# =====================================
# DocPad

###
The DocPad Class
It extends the EventSystem from bal-util to provide system events
It allows us to support multiple instances of docpad at the same time
###
class DocPad extends EventSystem

	# =================================
	# Variables

	# ---------------------------------
	# DocPad

	# DocPad's version number
	version: null

	# The express server instance bound to docpad
	server: null

	# The caterpillar instance bound to docpad
	logger: null


	# ---------------------------------
	# Models

	# File Model
	FileModel: FileModel

	# Document Model
	DocumentModel: DocumentModel


	# ---------------------------------
	# Collections

	# Query Collection
	QueryCollection: QueryCollection

	# Elements Collection
	ElementsCollection: ElementsCollection

	# Scripts Collection
	ScriptsCollection: ScriptsCollection

	# Styles Collection
	StylesCollection: StylesCollection

	# Blocks
	blocks: null
	### {
		# A collection of meta elements
		meta: null  # Elements Collection

		# A collection of script elements
		scripts: null  # Scripts Collection

		# Collection of style elements
		styles: null  # Styles Collection
	} ###

	# Collections
	collections: null
	### {
		# Documents collection
		documents: null  # QueryEngine Collection

		# Files collection
		files: null  # QueryEngine Collection

		# Layouts collection
		layouts: null  # QueryEngine Collection
	} ###

	# Database collection
	database: null  # QueryEngine Collection

	# Documents collection
	# only here for b/c
	documents: null  # QueryEngine Collection


	# ---------------------------------
	# Plugins

	# Plugins that are loading really slow
	slowPlugins: null  # {}

	# Plugins which DocPad have found
	foundPlugins: null  # {}

	# Loaded plugins indexed by name
	loadedPlugins: null  # {}

	# A listing of all the available extensions for DocPad
	exchange: null  # {}


	# -----------------------------
	# Paths

	# The DocPad directory
	corePath: pathUtil.join(__dirname, '..')

	# The DocPad library directory
	libPath: __dirname

	# The main DocPad file
	mainPath: pathUtil.join(__dirname, 'docpad')

	# The DocPad package.json path
	packagePath: pathUtil.join(__dirname, '..', 'package.json')

	# The DocPad local NPM path
	npmPath: pathUtil.join(__dirname, '..', 'node_modules', 'npm', 'bin', 'npm-cli.js')


	# -----------------------------
	# Configuration

	###
	Instance Configuration
	Loaded from:
		- the passed instanceConfiguration when creating a new DocPad instance
		- the detected websiteConfiguration inside ./docpad.cson>docpad
		- the following configuration
	###
	config:

		# -----------------------------
		# Plugins

		# Force re-install of all plugin dependencies
		force: false

		# Whether or not we should enable plugins that have not been listed or not
		enableUnlistedPlugins: true

		# Plugins which should be enabled or not pluginName: pluginEnabled
		enabledPlugins: null  # {}

		# Whether or not we should skip unsupported plugins
		skipUnsupportedPlugins: true

		# Configuration to pass to any plugins pluginName: pluginConfiguration
		plugins: null  # {}

		# Where to fetch the exchange information from
		exchangeUrl: 'https://raw.github.com/bevry/docpad-extras/docpad-5.x/exchange.json'


		# -----------------------------
		# Website Paths

		# The website directory
		rootPath: '.'

		# The website's package.json path
		packagePath: 'package.json'

		# The website's docpad.cson path
		configPath: 'docpad.cson'

		# The website's out directory
		outPath: 'out'

		# The website's src directory
		srcPath: 'src'

		# The website's documents directories
		documentsPath: null
		documentsPaths: [
			pathUtil.join('src', 'documents')
		]

		# The website's files directories
		filesPath: null
		filesPaths: [
			pathUtil.join('src', 'files')
			pathUtil.join('src', 'public')
		]

		# The website's layouts directory
		layoutsPath: null
		layoutsPaths: [
			pathUtil.join('src', 'layouts')
		]

		# Plugin directories to load
		pluginPaths: []

		# The website's plugins directory
		pluginsPaths: ['node_modules','plugins']


		# -----------------------------
		# Server

		# Server
		# A express server that we want docpad to use
		server: null

		# Extend Server
		# Whether or not we should extend the server with extra middleware and routing
		extendServer: true

		# Port
		# The port that the server should use
		port: 9778

		# Max Age
		# The caching time limit that is sent to the client
		maxAge: false


		# -----------------------------
		# Logging

		# Log Level
		# Which level of logging should we actually output
		logLevel: (if process.argv.has('-d') then 7 else 6)

		# Logger
		# A caterpillar instance if we already have one
		logger: null

		# Growl
		# Whether or not to send notifications to growl when we have them
		growl: true


		# -----------------------------
		# Other

		# Node Path
		# The location of our node executable
		nodePath: if /node$/.test(process.execPath) then process.execPath else 'node'

		# Git Path
		# The location of our git executable
		gitPath: if /^win/.test(process.platform) then 'git.cmd' else 'git'

		# Template Data
		# What data would you like to expose to your templates
		templateData: null  # {}

		# Report Errors
		# Whether or not we should report our errors back to DocPad
		reportErrors: true

		# Check Version
		# Whether or not to check for newer versions of DocPad
		checkVersion: true

		# Collections
		# A hash of functions that create collections
		collections: null  # {}


	# =================================
	# Initialization Functions

	# Construct DocPad
	# next(err)
	constructor: (config={},next) ->
		# Prepare
		docpad = @

		# Ensure certain functions always have the scope of this instance
		_.bindAll(@, 'createDocument', 'createFile')

		# Allow DocPad to have unlimited event listeners
		@setMaxListeners(0)

		# Initialize a default logger
		@logger = new caterpillar.Logger
			transports:
				formatter: module: module
		@setLogLevel(6)
		logger = @logger

		# Bind the error handler, so we don't crash on errors
		process.setMaxListeners(0)
		process.on 'uncaughtException', (err) ->
			docpad.error(err)

		# Dereference and initialise advanced variables
		@slowPlugins = {}
		@foundPlugins = {}
		@loadedPlugins = {}
		@exchange = {}
		@collections = {}
		@blocks = {}
		@config = _.clone(@config)
		@config.enabledPlugins = {}
		@config.plugins = {}
		@config.templateData = {}
		@config.collections = {}
		@config.documentsPaths = @config.documentsPaths.slice()
		@config.filesPaths = @config.filesPaths.slice()
		@config.layoutsPaths = @config.layoutsPaths.slice()
		@config.pluginPaths = @config.pluginPaths.slice()
		@config.pluginsPaths = @config.pluginsPaths.slice()

		# Initialize the collections
		@database = new @QueryCollection()

		# Apply configuration
		@loadConfiguration config, {}, (err) =>
			# Error?
			return @error(err)  if err

			# Collections
			@collections.documents = @database.createLiveChildCollection().setQuery('isDocument', fullPath: $beginsWith: @config.documentsPaths)
			@collections.files = @database.createLiveChildCollection().setQuery('isFile', fullPath: $beginsWith: @config.filesPaths)
			@collections.layouts = @database.createLiveChildCollection().setQuery('isLayout', fullPath: $beginsWith: @config.layoutsPaths)
			@documents = @collections.documents  # only here for b/c

			# Blocks
			@blocks.meta = new @ElementsCollection()
			@blocks.scripts = new @ScriptsCollection()
			@blocks.styles = new @StylesCollection()
			@blocks.meta.add([
				'<meta http-equiv="X-Powered-By" content="DocPad"/>'
			])

			# Load Airbrake if we want to reportErrors
			if @config.reportErrors and /win/.test(process.platform) is false
				airbrake = require('airbrake').createClient('e7374dd1c5a346efe3895b9b0c1c0325')

			# Version Check
			@compareVersion()

			# Log
			logger.log 'debug', 'DocPad loaded succesfully'
			logger.log 'debug', 'Loaded the following plugins:', _.keys(@loadedPlugins).sort().join(', ')

			# Next
			return next?()


	# =================================
	# Configuration

	# Clean
	clean: ->
		# Perform a complete clean of our collections
		@database.reset([])
		@blocks.meta.reset([])
		@blocks.scripts.reset([])
		@blocks.styles.reset([])

		# Chain
		@

	# Load a configuration url
	# next(err,parsedData)
	loadConfigUrl: (configUrl,next) ->
		# Log
		@logger.log 'debug', "Loading configuration url: #{configUrl}"

		# Read the url using balUtil
		balUtil.readPath configUrl, (err,data) ->
			return next(err)  if err
			# Read the string using CSON
			CSON.parse(data.toString(),next)

		# Chain
		@

	# Load a configuration file
	# CSON supports CSON and JSON
	# next(err,parsedData)
	loadConfigPath: (configPath,next) ->
		# Log
		@logger.log 'debug', "Loading configuration path: #{configPath}"

		# Check that it exists
		pathUtil.exists configPath, (exists) ->
			return next?(null,null)  unless exists
			# Read the path using CSON
			CSON.parseFile(configPath, next)

		# Chain
		@

	# Load collections
	loadCollections: (next) ->
		# Prepare
		docpad = @
		database = @database
		collections = @collections
		@config.collections or= {}

		# Group
		tasks = new balUtil.Group (err) =>
			docpad.error(err)  if err
			return next?()

		# Cycle
		_.each @config.collections, (fn,name) ->
			tasks.push (complete) ->
				if fn.length is 2 # callback
					fn database, (err,collection) ->
						docpad.error(err)  if err
						if collection
							collection.live(true)  # make it a live collection
							collections[name] = collection  # apply the collection
						complete()
				else
					collection = fn(database)
					if collection
						collection.live(true)  # make it a live collection
						collections[name] = collection  # apply the collection
					complete()

		# Run
		tasks.async()

		# Chain
		@

	# Load Configuration
	loadConfiguration: (instanceConfig={},options={},next) ->
		# Prepare
		docpad = @
		logger = @logger

		# Options
		options.blocking ?= true

		# Exits
		fatal = (err) ->
			docpad.fatal(err,next)
		complete = (err) ->
			nextStep = ->
				docpad.finish 'loading', (lockError) ->
					return fatal(lockError)  if lockError
					return next?(err)
			if options.blocking
				docpad.unblock 'generating, watching, serving', (lockError) ->
					return fatal(lockError)  if lockError
					nextStep()
			else
				nextStep()

		# Define loading
		startLoading = =>
			# Start loading
			docpad.start 'loading', (lockError) =>
				return fatal(lockError)  if lockError

				# Prepare
				instanceConfig.rootPath or= process.cwd()
				instanceConfig.packagePath or= @config.packagePath
				instanceConfig.configPath or= @config.configPath
				docpadPackagePath = @packagePath
				websitePackagePath = pathUtil.resolve(instanceConfig.rootPath, instanceConfig.packagePath)  # only here for b/c
				websiteConfigPath = pathUtil.resolve(instanceConfig.rootPath, instanceConfig.configPath)
				websitePackageConfig = {}
				websiteConfig = {}

				# Async
				tasks = new balUtil.Group (err) =>
					return fatal(err)  if err

					# Merge Configuration (not deep!)
					config = _.extend(
						{}
						@config
						websitePackageConfig  # only here for b/c
						websiteConfig
						instanceConfig
					)

					# Merge enabled plugins
					config.enabledPlugins = _.extend(
						{}
						@config.enabledPlugins or {}
						websiteConfig.enabledPlugins or {}
						instanceConfig.enabledPlugins or {}
					)

					# Merge template data
					config.templateData = _.extend(
						{}
						@config.templateData or {}
						websiteConfig.templateData or {}
						instanceConfig.templateData or {}
					)

					# Apply merged configuration
					@config = config

					# Options
					@server = @config.server  if @config.server

					# Noramlize and resolve the configuration paths
					@config.rootPath = pathUtil.normalize(@config.rootPath or process.cwd())
					@config.outPath = pathUtil.resolve(@config.rootPath, @config.outPath)
					@config.srcPath = pathUtil.resolve(@config.rootPath, @config.srcPath)

					# Documents, Files, Layouts, Plugins paths
					for type in ['documents','files','layouts','plugins']
						typePath = @config[type+'Path']
						typePaths = @config[type+'Paths']
						typePaths.push(typePath)  if typePath
						for typePath,key in typePaths
							typePaths[key] = pathUtil.resolve(@config.rootPath,typePath)

					# Logger
					@logger = @config.logger  if @config.logger
					@setLogLevel(@config.logLevel)

					# Async
					postTasks = new balUtil.Group (err) =>
						return fatal(err)  if err
						return complete()
					postTasks.total = 2

					# Load collections
					@loadCollections(postTasks.completer())

					# Initialize
					@loadPlugins(postTasks.completer())


				# Prepare configuration loading
				tasks.total = 3

				# Load DocPad Configuration
				@loadConfigPath docpadPackagePath, (err,data) ->
					return tasks.complete(err)  if err
					data or= {}

					# Version
					docpad.version = data.version
					airbrake.appVersion = docpad.version  if airbrake

					# Compelte the loading
					tasks.complete()

				# Load Website Package Configuration
				# only here for b/c
				@loadConfigPath websitePackagePath, (err,data) ->
					return tasks.complete(err)  if err
					data or= {}

					# Apply data to parent scope
					websitePackageConfig = data.docpad or {}

					# Compelte the loading
					tasks.complete()

				# Load Website Configuration
				@loadConfigPath websiteConfigPath, (err,data) ->
					return tasks.complete(err)  if err
					data or= {}

					# Apply data to parent scope
					websiteConfig = data

					# Compelte the loading
					tasks.complete()

		# Block other events
		if options.blocking
			docpad.block 'generating, watching, serving', (lockError) =>
				return fatal(lockError)  if lockError
				startLoading()
		else
			startLoading()

		# Chain
		@


	# Init Node Modules
	# next(err,results)
	initNodeModules: (opts={}) ->
		# Prepare
		opts.npmPath = @npmPath
		opts.nodePath = @config.nodePath
		opts.force = @config.force

		# Forward
		balUtil.initNodeModules(opts)

		# Chain
		@


	# =================================
	# Logging

	# Set Log Level
	setLogLevel: (level) ->
		@logger.setLevel(level)
		@

	# Are we debugging?
	getLogLevel: ->
		return @config.logLevel

	# Are we debugging?
	getDebugging: ->
		return @getLogLevel() is 7

	# Handle a fatal error
	fatal: (err) ->
		return @  unless err
		@error err, 'err', ->
			process.exit(-1)


	# Handle an error
	error: (err,type='err',next) ->
		# Prepare
		docpad = @
		logger = @logger

		# Check
		if !err or err.logged
			next?()
			return @

		# Log the error only if it hasn't been logged already
		err.logged = true
		err = new Error(err)  unless err instanceof Error
		err.logged = true
		logger.log type, 'An error occured:', err.message, err.stack

		# Report the error back to DocPad using airbrake
		if docpad.config.reportErrors and airbrake
			err.params =
				docpadVersion: @version
				docpadConfig: @config
			airbrake.notify err, (airbrakeErr,airbrakeUrl) ->
				console.log(airbrakeErr)  if airbrakeErr
				console.log('Error has been logged to:', airbrakeUrl)
				next?()
		else
			next?()

		# Chain
		@

	# Handle a warning
	warn: (message,err,next) ->
		# Prepare
		docpad = @
		logger = @logger

		# Log
		logger.log('warn', message)
		docpad.error(err, 'warn', next)

		# Chain
		@

	# Perform a growl notification
	notify: (args...) =>
		# Check if we want to use growl
		return @  unless @config.growl

		# Try
		try
			# Load growl
			growl = require('growl')

			# Use growl
			growl.apply(growl,args)

		# Catch
		catch err
			# Ignore

		# Chain
		@


	# =================================
	# Models

	# Instantiate a File
	createFile: (data={},options={}) ->
		# Prepare
		options = _.extend(
			logger: @logger
			outDirPath: @config.outPath
		,options)

		# Create and return
		file = new @FileModel(data,options)

		# Return
		return file

	# Instantiate a Document
	createDocument: (data={},options={}) ->
		# Prepare
		docpad = @
		options = _.extend(
			logger: @logger
			outDirPath: @config.outPath
			layouts: @collections.layouts
		,options)

		# Create and return
		document = new @DocumentModel(data,options)

		# Bubble
		document.on 'render', (args...) ->
			docpad.emitSync 'render', args...
		document.on 'renderDocument', (args...) ->
			docpad.emitSync 'renderDocument', args...

		# Return
		return document


	# =================================
	# Plugins

	# Get a plugin by it's name
	getPlugin: (pluginName) ->
		@loadedPlugins[pluginName]

	# Check if we have any plugins
	hasPlugins: ->
		return _.isEmpty(@loadedPlugins) is false

	# Load Plugins
	loadPlugins: (next) ->
		# Prepare
		docpad = @
		logger = @logger
		@slowPlugins = {}
		snore = @createSnore ->
			logger.log 'notice', "We're preparing your plugins, this may take a while the first time. Waiting on the plugins: #{_.keys(docpad.slowPlugins).join(', ')}"

		# Async
		tasks = new balUtil.Group (err) ->
			docpad.slowPlugins = {}
			snore.clear()
			return next?(err)

		# Load website plugins
		_.each @config.pluginsPaths or [], (pluginsPath) =>
			exists = pathUtil.existsSync(pluginsPath)
			if exists
				tasks.push (complete) =>
					@loadPluginsIn(pluginsPath, complete)

		# Load specific plugins
		_.each @config.pluginPaths or [], (pluginPath) =>
			exists = pathUtil.existsSync(pluginPath)
			if exists
				tasks.push (complete) =>
					@loadPlugin(pluginPath, complete)

		# Execute the loading asynchronously
		tasks.async()

		# Chain
		@

	# Loaded Plugin
	# Checks if a plugin was loaded succesfully
	# next(err,loaded)
	loadedPlugin: (pluginName,next) ->
		# Prepare
		docpad = @
		# Once loading has finished
		docpad.onceFinished 'loading', (err) ->
			return next(err)  if err
			loaded = docpad.loadedPlugins[pluginName]?
			return next(null,loaded)

	# Load PLugin
	# next(err)
	loadPlugin: (fileFullPath,_next) ->
		# Prepare
		docpad = @
		logger = @logger
		config = @config
		next = (err) ->
			# Remove from slow plugins
			delete docpad.slowPlugins[pluginName]
			# Forward
			return _next(err)

		# Prepare variables
		loader = new PluginLoader(
			dirPath: fileFullPath
			docpad: docpad
			BasePlugin: BasePlugin
		)
		pluginName = loader.pluginName
		enabled = (
			(config.enableUnlistedPlugins  and  config.enabledPlugins[pluginName]? is false)  or
			config.enabledPlugins[pluginName] is true
		)

		# Check if we already exist
		if docpad.foundPlugins[pluginName]?
			return _next()

		# Add to loading stores
		docpad.slowPlugins[pluginName] = true
		docpad.foundPlugins[pluginName] = true

		# Check
		unless enabled
			# Skip
			logger.log 'debug', "Skipped plugin: #{pluginName}"
			return next()
		else
			# Load
			logger.log 'debug', "Loading plugin: #{pluginName}"
			loader.exists (err,exists) ->
				return next(err)  if err or not exists
				loader.unsupported (err,unsupported) ->
					return next(err)  if err
					if unsupported
						if unsupported is 'version' and  docpad.config.skipUnsupportedPlugins is false
							logger.log 'warn', "Continuing with the unsupported plugin: #{pluginName}"
						else
							if unsupported is 'type'
								logger.log 'debug', "Skipped the unsupported plugin: #{pluginName} due to #{unsupported}"
							else
								logger.log 'warn', "Skipped the unsupported plugin: #{pluginName} due to #{unsupported}"
							return next()
					loader.install (err) ->
						return next(err)  if err
						loader.load (err) ->
							return next(err)  if err
							loader.create {}, (err,pluginInstance) ->
								return next(err)  if err
								# Add to plugin stores
								docpad.loadedPlugins[loader.pluginName] = pluginInstance
								# Log completion
								logger.log 'debug', "Loaded plugin: #{pluginName}"
								# Forward
								return next()

	# Load Plugins
	loadPluginsIn: (pluginsPath, next) ->
		# Prepare
		docpad = @
		logger = @logger

		# Load Plugins
		logger.log 'debug', "Plugins loading for: #{pluginsPath}"
		balUtil.scandir(
			# Path
			path: pluginsPath

			# Ignore common patterns
			ignorePatterns: true

			# Skip files
			fileAction: false

			# Handle directories
			dirAction: (fileFullPath,fileRelativePath,_nextFile) ->
				# Prepare
				pluginName = pathUtil.basename(fileFullPath)
				return _nextFile(null,false)  if fileFullPath is pluginsPath
				nextFile = (err,skip) ->
					if err
						docpad.warn("Failed to load the plugin: #{pluginName} at #{fileFullPath}. The error follows:",err)
					return _nextFile(null,skip)

				# Forward
				docpad.loadPlugin fileFullPath, (err) ->
					return nextFile(err,true)

			# Next
			next: (err) ->
				logger.log 'debug', "Plugins loaded for: #{pluginsPath}"
				return next?(err)
		)

		# Chain
		@


	# =================================
	# Utilities

	# ---------------------------------
	# Utilities: Misc

	# Create snore
	createSnore: (message) ->
		# Prepare
		logger = @logger

		# Create snore object
		snore =
			snoring: false
			timer: setTimeout(
				->
					snore.clear()
					snore.snoring = true
					if _.isFunction(message)
						message()
					else
						logger.log 'notice', message
				5000
			)
			clear: ->
				if snore.timer
					clearTimeout(snore.timer)
					snore.timer = false


	# Compare current DocPad version to the latest
	compareVersion: ->
		return @  unless @config.checkVersion

		# Prepare
		docpad = @
		notify = @notify
		logger = @logger

		# Check
		balUtil.packageCompare
			local: pathUtil.join(docpad.corePath, 'package.json')
			remote: 'https://raw.github.com/bevry/docpad/master/package.json'
			newVersionCallback: (details) ->
				docpad.notify "There is a new version of #{details.local.name} available"
				docpad.logger.log 'notice', """
					There is a new version of #{details.local.name} available, you should probably upgrade...
					current version:  #{details.local.version}
					new version:      #{details.remote.version}
					grab it here:     #{details.remote.homepage}
					"""
		@


	# ---------------------------------
	# Utilities: Rendering

	# Get Template Data
	getTemplateData: (userData) ->
		# Prepare
		userData or= {}
		docpad = @

		# Initial merge
		templateData = _.extend({
			require: require
			include: (subRelativePath) ->
				fullRelativePath = @document.relativeDirPath+'/'+subRelativePath
				result = docpad.database.findOne(relativePath: fullRelativePath)
				if result
					return result.get('contentRendered') or result.get('content')
				else
					warn = "The file #{relativeBase} was not found..."
					docpad.warn(warn)
					return warn
			docpad: @
			database: @database
			collections: @collections
			document: null
			site: {}
			blocks: @blocks
		}, @config.templateData, userData)

		# Add site data
		templateData.site.date or= new Date()
		templateData.site.keywords or= []
		if _.isString(templateData.site.keywords)
			templateData.site.keywords = templateData.site.keywords.split(/,\s*/g)

		# Return
		return templateData

	# Render a document
	# next(err,document)
	render: (document,templateData,next) ->
		templateData = _.extend({},templateData)
		templateData.document = document.toJSON()
		templateData.documentModel = document
		document.render templateData, (err) =>
			@error(err)  if err
			return next?(err,document)

		# Chain
		@

	# Render a document
	# next(err,document)
	prepareAndRender: (document,templateData,next) ->
		# Prepare
		docpad = @

		# Normalize the document
		document.normalize (err) ->
			return next?(err)  if err
			# Load the document
			document.load (err) ->
				return next?(err)  if err
				# Contextualize the document
				document.contextualize (err) ->
					return next?(err) if err
					# Render the document
					docpad.render document, templateData, (err) ->
						return next?(err,document)

		# Chain
		@


	# ---------------------------------
	# Utilities: Files

	# Parse a directory
	# next(err)
	parseDirectory: (opts={}) ->
		# Prepare
		docpad = @
		logger = @logger

		# Extract
		{path,createFunction,resultCollection,next} = opts

		# Check if the directory exists
		unless pathUtil.existsSync(path)
			# Log
			logger.log 'debug', "Skipped directory: #{path} (it does not exist)"

			# Forward
			return next?()

		# Log
		logger.log 'debug', "Parsing directory: #{path}"

		# Files
		balUtil.scandir(
			# Path
			path: path

			# Ignore common patterns
			ignorePatterns: true

			# File Action
			fileAction: (fileFullPath,fileRelativePath,nextFile,fileStat) ->
				# Prepare
				data =
					fullPath: fileFullPath
					relativePath: fileRelativePath
				options =
					stat: fileStat

				# Create file
				file = createFunction(data,options)
				file.load (err) ->
					# Log
					logger.log 'debug', "Loading file: #{fileRelativePath}"

					# Check
					if err
						docpad.warn("Failed to load the file: #{fileRelativePath}. The error follows:", err)
						return nextFile()

					# Prepare
					fileIgnored = file.get('ignored')
					fileParse = file.get('parse')

					# Ignored?
					if fileIgnored or (fileParse? and !fileParse)
						logger.log 'info', 'Skipped manually ignored file:', file.get('relativePath')
						return nextFile()
					else
						logger.log 'debug', 'Loaded file:', file.get('relativePath')

					# Store Document
					resultCollection.add(file)  if resultCollection?

					# Forward
					return nextFile()

			# Next
			next: (err) ->
				# Log
				logger.log 'debug', "Parsed directory: #{path}"

				# Forward
				return next?(err)
		)

		# Chain
		@

	# Contextualize Files
	# next(err)
	contextualizeFiles: (opts={}) ->
		# Prepare
		docpad = @
		logger = @logger

		# Extract
		{collection,next} = opts

		# Log
		logger.log 'debug', "Contextualizing #{collection.length} files"

		# Async
		tasks = new balUtil.Group (err) ->
			return next?(err)  if err
			logger.log 'debug', "Contextualized #{collection.length} files"
			next?()

		# Fetch
		collection.forEach (file) ->  tasks.push (complete) ->
			file.contextualize(complete)

		# Async
		tasks.async()

		# Chain
		@

	# Render documents
	# next(err)
	renderDocuments: (opts={}) ->
		# Prepare
		docpad = @
		logger = @logger

		# Extract
		{collection,next} = opts

		# Log
		logger.log 'debug', "Rendering #{collection.length} files"

		# Async
		tasks = new balUtil.Group (err) ->
			return next?(err)  if err
			# After
			docpad.emitSync 'renderAfter', {}, (err) ->
				logger.log 'debug', "Rendered #{collection.length} files"  unless err
				return next?(err)

		# Get the template data
		templateData = @getTemplateData(
			# only here for b/c
			documents: @documents.sortArray(date:-1)
		)

		# Push the render tasks
		collection.forEach (file) ->  tasks.push (complete) ->
			dynamic = file.get('dynamic')
			render = file.get('render')
			if dynamic or (render? and !render)
				return complete()
			docpad.render(file,templateData,complete)

		# Fire the render tasks
		if tasks.total
			@emitSync 'renderBefore', {collection,templateData}, (err) =>
				return next?(err)  if err
				tasks.async()
		else
			tasks.exit()

		# Chain
		@

	# Write documents
	# next(err)
	writeFiles: (opts={}) ->
		# Prepare
		docpad = @
		logger = @logger

		# Extract
		{collection,next} = opts

		# Log
		logger.log 'debug', "Writing #{collection.length} files"

		# Async
		tasks = new balUtil.Group (err) ->
			# After
			logger.log 'debug', "Wrote #{collection.length} files"  unless err
			return next?(err)

		# Cycle
		collection.forEach (file) ->  tasks.push (complete) ->
			# Fetch
			outPath = file.get('outPath')
			relativePath = file.get('relativePath')

			# Skip
			dynamic = file.get('dynamic')
			render = file.get('render')
			write = file.get('write')
			if dynamic or (render? and !render) or (write? and !write)
				return complete()

			# Ensure path
			balUtil.ensurePath pathUtil.dirname(outPath), (err) ->
				# Error
				return complete(err)  if err

				# Write file
				logger.log 'debug', "Writing file: #{relativePath}"
				if file.writeRendered?
					file.writeRendered(complete)
				else
					file.write(complete)

		# Async
		tasks.async()

		# Chain
		@


	# ---------------------------------
	# Utilities: Exchange

	# Get Exchange
	# Get the exchange data
	# Requires internet access
	# next(err,exchange)
	getExchange: (next) ->
		# Check if it is stored locally
		return next(null,@exchange)  unless _.isEmpty(@exchange)

		# Otherwise fetch it from the exchangeUrl
		@loadConfigUrl @config.exchangeUrl, (err,parsedData) ->
			return next(err)  if err
			@exchange = parsedData
			return next(null,parsedData)

		# Chain
		@


	# ---------------------------------
	# Utilities: Skeletons

	# Get Skeletons
	# Get all the available skeletons for us and their details
	# next(err,skeletons)
	getSkeletons: (next) ->
		@getExchange (err,exchange) ->
			return next(err)  if err
			skeletons = exchange.skeletons
			return next(null,skeletons)
		@

	# Get Skeleton
	# Returns a skeleton's details
	# next(err,skeletonDetails)
	getSkeleton: (skeletonId,next) ->
		@getSkeletons (err,skeletons) ->
			return next(err)  if err
			skeletonDetails = skeletons[skeletonId]
			return next(null,skeletonDetails)
		@

	# Install a Skeleton to a Directory
	# next(err)
	installSkeleton: (skeletonId,destinationPath,next) ->
		# Prepare
		docpad = @
		logger = @logger
		packagePath = pathUtil.join(destinationPath, 'package.json')

		# Grab the skeletonDetails
		@getSkeleton skeletonId, (err,skeletonDetails) ->
			# Error?
			return docpad.error(err)  if err

			# Configure
			repoConfig =
				gitPath: docpad.config.gitPath
				path: destinationPath
				url: skeletonDetails.repo
				branch: skeletonDetails.branch
				remote: 'skeleton'
				output: docpad.getDebugging()
				next: (err) ->
					# Error?
					return docpad.error(err)  if err

					# Initialise the Website's modules for the first time
					docpad.initNodeModules(
						path: destinationPath
						next: (err) =>
							# Error?
							return docpad.error(err)  if err

							# Done
							return next?()
					)

			# Check if the skeleton path already exists
			balUtil.ensurePath destinationPath, (err) ->
				# Error?
				return docpad.error(err)  if err

				# Initalize the git repository
				balUtil.initGitRepo(repoConfig)

		# Chain
		@




	# =================================
	# Actions

	# Get the arguments for the action
	# Using this contains the transparency with using opts, and not using opts
	getActionArgs: (opts,next) ->
		if typeof opts is 'function' and next? is false
			next = opts
			opts = {}
		else
			opts or= {}
		next or= opts.next or null
		return {next,opts}

	# Perform an action
	# next(err)
	action: (action,opts={},next) ->
		# Prepare
		{opts,next} = @getActionArgs(opts,next)
		logger = @logger

		# Multiple actions?
		actions = action.split /[,\s]+/g
		if actions.length > 1
			tasks = new balUtil.Group(next)
			tasks.total = actions.length
			for action in actions
				@action action, tasks.completer()
			return @

		# Log
		logger.log 'debug', "Performing the action #{action}"

		# Handle
		switch action
			when 'install', 'update'
				@installAction opts, (err) =>
					return @fatal(err)  if err
					return next?()

			when 'skeleton', 'scaffold'
				@skeletonAction opts, (err) =>
					return @fatal(err)  if err
					return next?()

			when 'generate'
				@generateAction opts, (err) =>
					return @fatal(err)  if err
					return next?()

			when 'clean'
				@cleanAction opts, (err) =>
					return @fatal(err)  if err
					return next?()

			when 'render'
				@renderAction opts, (err,data) =>
					return @fatal(err)  if err
					return next?(err,data)

			when 'watch'
				@watchAction opts, (err) =>
					return @fatal(err)  if err
					return next?()

			when 'server', 'serve'
				@serverAction opts, (err) =>
					return @fatal(err)  if err
					return next?()

			else
				@runAction opts, (err) =>
					return @fatal(err)  if err
					return next?()

		# Chain
		@



	# ---------------------------------
	# Install

	# Install
	# next(err)
	installAction: (opts,next) ->
		# Prepare
		{opts,next} = @getActionArgs(opts,next)
		docpad = @
		logger = @logger

		# Re-Initialise the Website's modules
		@initNodeModules(
			path: @config.rootPath
			next: (err) ->
				# Forward on error?
				return next?(err)  if err

				# Re-load configuration
				docpad.loadConfiguration {}, {blocking:false}, (err) ->
					# Forward
					return next?(err)
		)

		# Chain
		@

	# Clean
	# next(err)
	cleanAction: (opts,next) ->
		# Prepare
		logger = @logger

		# Log
		logger.log 'debug', 'Cleaning files'

		# Files
		balUtil.rmdirDeep @config.outPath, (err,list,tree) ->
			logger.log 'debug', 'Cleaned files'  unless err
			return next?()

		# Chain
		@


	# ---------------------------------
	# Generate

	# Parse the files
	generateParse: (next) ->
		# Prepare
		docpad = @
		logger = @logger
		config = docpad.config

		# Before
		@emitSync 'parseBefore', {}, (err) ->
			return next?(err)  if err

			# Log
			logger.log 'debug', 'Parsing everything'

			# Tasks
			tasks = new balUtil.Group (err) ->
				# Log
				logger.log 'debug', 'Parsed everything'
				logger.log 'debug', 'Contextualizing everything'

				# Check
				if err
					docpad.warn("Failed to parse everything. The error follows:",err)
					return next?(err)

				# Contextualize
				docpad.generateParseContextualize (err) ->
					return next?(err)  if err

					# After
					docpad.emitSync 'parseAfter', {}, (err) ->
						if err
							docpad.warn("Failed to contextualize everything. The error follows:",err)
						else
							logger.log('debug', 'Contextualized everything')
						return next?(err)

			# Documents
			_.each config.documentsPaths, (documentsPath) ->  tasks.push (complete) ->
				docpad.parseDirectory(
					path: documentsPath
					createFunction: docpad.createDocument
					resultCollection: docpad.database
					next: complete
				)

			# Files
			_.each config.filesPaths, (filesPath) ->  tasks.push (complete) ->
				docpad.parseDirectory(
					path: filesPath
					createFunction: docpad.createFile
					resultCollection: docpad.database
					next: complete
				)

			# Layouts
			_.each config.layoutsPaths, (layoutsPath) ->  tasks.push (complete) ->
				docpad.parseDirectory(
					path: layoutsPath
					createFunction: docpad.createDocument
					resultCollection: docpad.database
					next: complete
				)

			# Async
			tasks.async()

		# Chain
		@


	# Generate Parse: Contextualize
	generateParseContextualize: (next) ->
		# Contextualize everything in the database
		@contextualizeFiles(
			collection: @database
			next: next
		)

		# Chain
		@


	# Generate render
	generateRender: (next) ->
		# Render all the documents
		@renderDocuments(
			collection: @collections.documents
			next: next
		)

		# Chain
		@


	# Write
	generateWrite: (next) ->
		# Prepare
		docpad = @
		logger = @logger

		# Log
		logger.log 'debug', 'Writing everything'

		# Before
		docpad.emitSync 'writeBefore', {}, (err) ->
			# Async
			tasks = new balUtil.Group (err) ->
				# After
				docpad.emitSync 'writeAfter', {}, (err) ->
					logger.log 'debug', 'Wrote everything'  unless err
					return next?(err)
			tasks.total = 2

			# Write all the documents
			docpad.writeFiles(
				collection: docpad.collections.documents
				next: tasks.completer()
			)

			# Write all the files
			docpad.writeFiles(
				collection: docpad.collections.files
				next: tasks.completer()
			)

		# Chain
		@


	# Generate
	generateAction: (opts,next) ->
		# Prepare
		{opts,next} = @getActionArgs(opts,next)
		docpad = @
		logger = @logger
		notify = @notify

		# Exits
		fatal = (err) ->
			docpad.fatal(err,next)
		complete = (err) ->
			docpad.unblock 'loading', (lockError) ->
				return fatal(lockError)  if lockError
				docpad.finish 'generating', (lockError) ->
					return fatal(lockError)  if lockError
					return next?(err)

		# Check plugin count
		unless docpad.hasPlugins()
			logger.log 'warn', """
				DocPad is currently running without any plugins installed. You probably want to install some: https://github.com/bevry/docpad/wiki/Plugins
				"""

		# Block loading
		docpad.block 'loading', (err) ->
			return fatal(err)  if err
			# Start generating
			docpad.start 'generating', (err) =>
				return fatal(err)  if err
				logger.log 'info', 'Generating...'
				notify (new Date()).toLocaleTimeString(), title: 'Website generating...'
				# Plugins
				docpad.emitSync 'generateBefore', server: docpad.server, (err) ->
					return complete(err)  if err
					# Continue
					pathUtil.exists docpad.config.srcPath, (exists) ->
						# Check
						if exists is false
							return complete new Error 'Cannot generate website as the src dir was not found'
						# Perform a complete clean of our collections
						docpad.clean()
						# Generate Parse
						docpad.generateParse (err) ->
							return complete(err)  if err
							# Generate Render (First Pass)
							docpad.generateRender (err) ->
								return complete(err)  if err
								# Generate Render (Second Pass)
								docpad.generateRender (err) ->
									return complete(err)  if err
									# Generate Write
									docpad.generateWrite (err) ->
										return complete(err)  if err
										# Unblock
										docpad.unblock 'loading', (err) ->
											return complete(err)  if err
											# Plugins
											docpad.emitSync 'generateAfter', server: docpad.server, (err) ->
												return complete(err)  if err
												# Finished
												docpad.finished 'generating', (err) ->
													return complete(err)  if err
													# Generated
													logger.log 'info', 'Generated'
													notify (new Date()).toLocaleTimeString(), title: 'Website generated'
													# Completed
													return complete()

		# Chain
		@


	# ---------------------------------
	# Render

	# Render Action
	renderAction: (opts,next) ->
		# Prepare
		{opts,next} = @getActionArgs(opts,next)
		docpad = @
		logger = @logger

		# Extract data
		data = opts.data or {}

		# Extract document
		if opts.filename
			document = @createDocument()
			document.set(
				filename: opts.filename
				fullPath: opts.filename
				data: opts.content
			)
			renderFunction = 'prepareAndRender'
		else if opts.document
			document = opts.document
			renderFunction = 'render'

		# Check
		return next? new Error('You must pass a document to the renderAction')  unless document

		# Exits
		fatal = (err) ->
			return docpad.fatal(err,next)
		complete = (err) ->
			docpad.finish 'render', (lockError) ->
				return fatal(lockError)  if lockError
				docpad.unblock 'loading, generating', (lockError) ->
					return fatal(lockError)  if lockError
					return next?(err,document)

		# Block loading
		docpad.block 'loading, generating', (lockError) ->
			return fatal(lockError)  if lockError
			docpad.start 'render', (lockError) ->
				return fatal(lockError)  if lockError
				# Render
				docpad[renderFunction](document, data, complete)
				return

		# Chain
		@


	# ---------------------------------
	# Watch

	# Watch
	watchAction: (opts,next) ->
		# Require
		watchr = require('watchr')

		# Prepare
		{opts,next} = @getActionArgs(opts,next)
		docpad = @
		database = @database
		logger = @logger
		srcWatcher = null
		configWatcher = null

		# Close our watchers
		close = ->
			if srcWatcher
				srcWatcher.close()
				srcWatcher = null
			if configWatcher
				configWatcher.close()
				configWatcher = null

		# Restart our watchers
		restart = (next) ->
			# Close our watchers
			close()

			# Start a group
			tasks = new balUtil.Group(next)
			tasks.total = 2

			# Watch the source
			srcWatcher = watchr.watch(
				path: docpad.config.srcPath
				listener: changeHandler
				next: tasks.completer()
				ignorePatterns: true
			)

			# Watch the config
			if pathUtil.existsSync(docpad.config.configPath)
				configWatcher = watchr.watch(
					path: docpad.config.configPath
					listener: ->
						docpad.loadConfiguration {}, {blocking:false}, ->
							changeHandler('config')
					next: tasks.completer()
				)
			else
				tasks.complete()

		# Change event handler
		changeHandler = (eventName,filePath,fileCurrentStat,filePreviousStat) ->
			###
			# Differential Rendering?
			if config.differentialRendering

				# Handle the action
				if eventName is 'unlink'
					changedFile.destroy()
				else if eventName is 'change'
					# Re-render just this file
					changedFile = database.findOne(fullPath: filePath)
					docpad.prepareAndRender changedFile, docpad.getTemplateData(), ->
						# Re-Render anything that references the changes
						pendingFiles = database.findAll(references: $has: changedFile).render()
						docpad.prepareAndRender pend

				else if eventName is 'new'

				# Re-Render anything that should always re-render
				database.findAll(referencesOthers: true).render()

			# Re-Render everything
			else
			###
			docpad.action 'generate', (err) ->
				docpad.error(err)  if err
				logger.log 'Regenerated due to file watch at '+(new Date()).toLocaleString()

		# A fatal error occured
		fatal = (err) ->
			docpad.fatal(err,next)

		# Start watching
		watch = ->
			# Block loading
			docpad.block 'loading', (lockError) ->
				return fatal(lockError)  if lockError
				docpad.start 'watching', (lockError) ->
					return fatal(lockError)  if lockError
					logger.log 'Watching setup starting...'
					restart (err) ->
						docpad.finish 'watching', (lockError) ->
							return fatal(lockError)  if lockError
							docpad.unblock 'loading', (lockError) ->
								return fatal(lockError)  if lockError
								logger.log 'Watching setup'
								return next?(err)

		# Stop watching if loading starts
		docpad.when 'loading:started', (err) ->
			return fatal(err)  if err
			close()

			# Start watching once loading has finished
			docpad.onceFinished 'loading', (err) ->
				return fatal(err)  if err
				return watch()

		# Stop watching if generating starts
		docpad.whenFinished 'generating:started', (err) ->
			return fatal(err)  if err
			close()

			# Start watching once generating has finished
			docpad.onceFinished 'generating', (err) ->
				return fatal(err)  if err
				return watch()

		# Watch
		watch()

		# Chain
		@


	# ---------------------------------
	# Run Action

	runAction: (opts,next) ->
		# Prepare
		{opts,next} = @getActionArgs(opts,next)
		docpad = @
		logger = @logger
		srcPath = @config.srcPath
		destinationPath = @config.rootPath

		# Run docpad
		runDocpad = =>
			@generateAction opts, (err) =>
				return @fatal(err)  if err
				@serverAction opts, (err) =>
					return @fatal(err)  if err
					@watchAction opts, (err) =>
						return @fatal(err)  if err
						return next?()

		# Check if we have the docpad structure
		if pathUtil.existsSync(srcPath)
			# We have the correct structure, so let's proceed with DocPad
			runDocpad()
		else
			# We don't have the correct structure
			# Check if we are running on an empty directory
			fsUtil.readdir destinationPath, (err,files) =>
				return fatal(err)  if err

				# Check if our directory is empty
				if files.length
					# It isn't empty, display a warning
					logger.log 'warn', """

						We couldn't find an existing DocPad project inside your current directory.
						If you're wanting to use a pre-made skeleton for the basis of your new project, then run DocPad again inside an empty directory.
						If you're wanting to start your new project from scratch, then refer to the Getting Started guide here:
							https://github.com/bevry/docpad/wiki/Getting-Started
						For more information on what this means, visit:
							https://github.com/bevry/docpad/wiki/Troubleshooting
						"""
					return next?()
				else
					@skeletonAction opts, (err) =>
						return @fatal(err)  if err
						runDocpad()

		# Chain
		@


	# ---------------------------------
	# Skeleton

	# Skeleton
	skeletonAction: (opts,next) ->
		# Prepare
		{opts,next} = @getActionArgs(opts,next)
		docpad = @
		logger = @logger
		skeletonId = @config.skeleton
		srcPath = @config.srcPath
		destinationPath = @config.rootPath
		selectSkeletonCallback = opts.selectSkeletonCallback or null

		# Exits
		fatal = (err) ->
			docpad.fatal(err,next)
		complete = (err) ->
			docpad.finish 'skeleton', (lockError) ->
				return fatal(lockError)  if lockError
				docpad.unblock 'generating, watching, serving', (lockError) ->
					return fatal(lockError)  if lockError
					return next?(err)
		useSkeleton = ->
			# Install Skeleton
			docpad.installSkeleton skeletonId, destinationPath, (err) ->
				return complete(err)  if err
				# Re-load configuration
				docpad.loadConfiguration {}, {blocking:false}, (err) ->
					# Forward
					return complete(err)

		# Block loading
		docpad.block 'generating, watching, serving', (lockError) ->
			return fatal(lockError)  if lockError

			# Start the skeleton process
			docpad.start 'skeleton', (lockError) ->
				return fatal(lockError)  if lockError

				# Check if already exists
				pathUtil.exists srcPath, (exists) ->
					# Check
					if exists
						logger.log 'warn', "Didn't place the skeleton as the desired structure already exists"
						return complete()

					# Do we already have a skeletonId selected?
					if skeletonId
						useSkeleton()
					else
						# Get the available skeletons
						docpad.getSkeletons (err,skeletons) ->
							# Check
							return complete(err)  if err
							# Provide selection to the interface
							selectSkeletonCallback skeletons, (err,_skeletonId) ->
								return fatal(err)  if err
								skeletonId = _skeletonId
								useSkeleton()

		# Chain
		@


	# ---------------------------------
	# Server

	# Server
	serverAction: (opts,next) ->
		# Require
		express = require('express')

		# Prepare
		{opts,next} = @getActionArgs(opts,next)
		docpad = @
		logger = @logger
		config = @config

		# Exists
		fatal = (err) ->
			docpad.fatal(err,next)
		complete = (err) ->
			# Finish
			docpad.finish 'serving', (lockError) ->
				return fatal(lockError)  if lockError
				# Unblock
				docpad.unblock 'loading', (err) ->
					return fatal(lockError)  if lockError
					return next?(err)

		# Block loading
		docpad.block 'loading', (lockError) ->
			return fatal(lockError)  if lockError
			docpad.start 'serving', (lockError) ->
				return fatal(lockError)  if lockError
				# Plugins
				docpad.emitSync 'serverBefore', {}, (err) ->
					return next?(err)  if err

					# Server
					docpad.server = express.createServer()  unless docpad.server
					server = docpad.server

					# Extend the server
					if config.extendServer
						# Configure the server
						server.configure ->
							# POST Middleware
							server.use express.bodyParser()
							server.use express.methodOverride()

							# DocPad Header
							server.use (req,res,next) ->
								tools = res.header('X-Powered-By').split /[,\s]+/g
								tools.push 'DocPad'
								tools = tools.join(',')
								res.header('X-Powered-By',tools)
								next()

							# Router Middleware
							server.use server.router

							# Routing
							server.use (req,res,next) ->
								# Check
								return next?()  unless docpad.database

								# Prepare
								cleanUrl = req.url.replace(/\?.*/,'')
								document = docpad.database.findOne(urls: '$in': cleanUrl)
								return next?()  unless document

								# Fetch
								contentTypeRendered = document.get('contentTypeRendered')
								url = document.get('url')
								dynamic = document.get('dynamic')
								contentRendered = document.get('contentRendered')

								# Content Type
								if contentTypeRendered
									res.contentType(contentTypeRendered)

								# Send
								if dynamic
									templateData = docpad.getTemplateData(req:req)
									docpad.render document, templateData, (err) ->
										contentRendered = document.get('contentRendered')
										if err
											docpad.error(err)
											return res.send(err.message, 500)
										else
											return res.send(contentRendered)
								else
									if contentRendered
										return res.send(contentRendered)
									else
										return next?()

							# Static
							if config.maxAge
								server.use(express.static config.outPath, maxAge: config.maxAge)
							else
								server.use(express.static config.outPath)

							# 404 Middleware
							server.use (req,res,next) ->
								return res.send(404)

						# Start the server
						result = server.listen config.port
						try
							address = server.address()
							serverHostname = if address.address is '0.0.0.0' then 'localhost' else address.address
							serverPort = address.port
							serverLocation = "http://#{serverHostname}:#{serverPort}/"
							serverDir = config.outPath
							logger.log 'info', "DocPad listening to #{serverLocation} on directory #{serverDir}"
						catch err
							logger.log 'err', "Could not start the web server, chances are the desired port #{config.port} is already in use"

					# Plugins
					docpad.emitSync 'serverAfter', {server}, (err) ->
						return complete(err)  if err
						# Complete
						logger.log 'debug', 'Server setup'  unless err
						return complete()

		# Chain
		@


# =====================================
# Export

# Export API
module.exports =
	DocPad: DocPad
	createInstance: (config,next) ->
		return new DocPad(config,next)
