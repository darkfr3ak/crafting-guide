###
Crafting Guide - mod_version_parser_v2.coffee

Copyright (c) 2014-2015 by Redwood Labs
All rights reserved.
###

CommandParserBase = require '../command_parser_base'
Item              = require '../item'
ModVersion        = require '../mod_version'
Recipe            = require '../recipe'
Stack             = require '../stack'
StringBuilder     = require '../string_builder'

########################################################################################################################

module.exports = class ModVersionParserV2 extends CommandParserBase

    # Class Methods ################################################################################

    @INTEGER = /[0-9]+/

    @PATTERN = /^[0-9.]{3} ?[0-9.]{3} ?[0-9.]{3}$/

    @STACK = /^([0-9]+) +(.*)$/

    # CommandParserBase Overrides ##################################################################

    _buildModel: (rawData, model)->
        @_buildModVersion rawData, model

    _unparseModel: (builder, model)->
        @_unparseModVersion builder, model

    # Command Methods ##############################################################################

    _command_description: (descriptionParts...)->
        if @_rawData.description? then throw new Error 'duplicate declaration of "description"'
        @_rawData.description = descriptionParts.join ', '

    _command_extras: (extraTerms...)->
        if not @_recipeData? then throw new Error 'cannot declare "extras" before "recipe"'
        if @_recipeData.extras? then throw new Error 'duplicate declaration of "extras"'

        @_recipeData.extras = []
        for term in extraTerms
            match = ModVersionParserV2.STACK.exec term
            if match?
                @_recipeData.extras.push quantity:parseInt(match[1]), name:match[2]
            else
                @_recipeData.extras.push quantity:1, name:term

    _command_gatherable: (gatherable)->
        if not @_itemData? then throw new Error 'cannot declare "gatherable" before "item"'
        if @_itemData.gatherable? then throw new Error 'duplicate declaration of "gatherable"'
        if not (gatherable in ['yes', 'no']) then throw new Error 'gatherable must be either "yes" or "no"'

        @_itemData.gatherable = (gatherable is 'yes')

    _command_item: (name='')->
        if not name.length > 0 then throw new Error 'the item name cannot be empty'

        @_itemData = name:name, line:@_lineNumber
        @_rawData.items ?= []
        @_rawData.items.push @_itemData

        @_recipeData = null

    _command_name: (name='')->
        if @_rawData.name? then throw new Error 'duplicate declaration of "name"'
        if not name.length > 0 then throw new Error 'the mod name cannot be empty'

        @_rawData.name = name

    _command_input: (inputNames...)->
        if not @_recipeData? then throw new Error 'cannot declare "input" before "recipe"'
        if @_recipeData.input? then throw new Error 'duplicate declaration of "input"'

        @_recipeData.input = []
        for name in inputNames
            if name.length is 0 then throw new Error 'input names cannot be empty'
            @_recipeData.input.push name

    _command_pattern: (pattern='')->
        if not @_recipeData? then throw new Error 'cannot declare "pattern" before "recipe"'
        if @_recipeData.pattern? then throw new Error 'duplicate declaration of "pattern"'
        if not ModVersionParserV2.PATTERN.test pattern
            throw new Error 'a pattern must have 9 digits using 0-9 for items and "." for an empty spot;
                spaces are optional'

        @_recipeData.pattern = pattern

    _command_quantity: (quantity)->
        if not @_recipeData? then throw new Error 'cannot declare "quantity" before "recipe"'
        if @_recipeData.quantity? then throw new Error 'duplicate declaration of "quantity"'
        if not ModVersionParserV2.INTEGER.test(quantity) then throw new Error 'quantity must be an integer'

        @_recipeData.quantity = parseInt quantity

    _command_recipe: ->
        if not @_itemData? then throw new Error 'cannot delcare "recipe" before "item"'

        @_recipeData = line:@_lineNumber
        @_itemData.recipes ?= []
        @_itemData.recipes.push @_recipeData

    _command_schema: -> # do nothing

    _command_tools: (toolNames...)->
        if not @_recipeData? then throw new Error 'cannot declare "tools" before "recipe"'
        if @_recipeData.tools? then throw new Error 'duplicate declaration of "tools"'

        @_recipeData.tools = []
        for name in toolNames
            if name.length is 0 then throw new Error 'tool names cannot be empty'
            @_recipeData.tools.push name

    _command_version: (version='')->
        if @_rawData.version? then throw new Error 'duplicate declaration of "version"'
        if version.length is 0 then throw new Error 'version cannot be empty'

        @_rawData.version = version

    # Object Creation Methods ######################################################################

    _buildModVersion: (modVersionData, modVersion)->
        if not modVersionData.name? then throw new Error 'the "name" declaration is required'
        if not modVersionData.version? then throw new Error 'the "version" declaration is required'

        if modVersionData.name isnt modVersion.name
            throw new Error "modVersionData name (#{modVersionData.name})
                must match the ModVersion (#{modVersion.name})"
        if modVersionData.version isnt modVersion.version
            throw new Error "modVersionData version (#{modVersionData.version})
                must match the ModVersion (#{modVersion.version})"

        modVersionData.description ?= ''
        modVersionData.items       ?= []

        modVersion.description = modVersionData.description

        for itemData in modVersionData.items
            @_handleErrors @_buildItem, modVersion, itemData

        return modVersion

    _buildItem: (modVersion, itemData)->
        @_lineNumber = itemData.line
        itemData.gatherable ?= false
        itemData.recipes    ?= []

        item = new Item name:itemData.name, isGatherable:itemData.gatherable
        modVersion.addItem item

        for recipeData in itemData.recipes
            @_handleErrors @_buildRecipe, modVersion, item, recipeData

        return item

    _buildRecipe: (modVersion, item, recipeData)->
        @_lineNumber = recipeData.line
        if not recipeData.input? then throw new Error 'the "input" declaration is required'
        if not recipeData.pattern? then throw new Error 'the "pattern" declaration is required'

        recipeData.quantity   ?= 1
        recipeData.extras     ?= []
        recipeData.tools      ?= []

        inputStacks = []
        for name in recipeData.input
            slug = _.slugify name
            modVersion.registerSlug slug, name
            inputStacks.push new Stack slug:slug, quantity:0

        for c in recipeData.pattern
            continue if c is '.'
            continue if c is ' '
            stack = inputStacks[parseInt(c)]
            if not stack? then throw new Error "there is no input #{c} in this recipe"
            stack.quantity += 1

        for i in [0...inputStacks.length]
            stack = inputStacks[i]
            if stack.quantity is 0
                name = modVersion.findName stack.slug
                throw new Error "#{name} is an input for this recipe, but it is not in the pattern"

        outputStacks = [ new Stack slug:item.slug, quantity:recipeData.quantity ]
        for extraData in recipeData.extras
            slug = _.slugify extraData.name
            modVersion.registerSlug slug, extraData.name
            outputStacks.push new Stack slug:slug, quantity:extraData.quantity

        toolStacks = []
        for name in recipeData.tools
            slug = _.slugify name
            modVersion.registerSlug slug, name
            toolStacks.push new Stack slug:slug, quantity:1

        attributes =
            input:    inputStacks
            name:     item.name
            pattern:  recipeData.pattern
            output:   outputStacks
            tools:    toolStacks

        recipe = new Recipe attributes
        item.addRecipe recipe
        return recipe

    # Un-parsing Methods ###########################################################################

    _unparseModVersion: (builder, modVersion)->
        itemList = _.values modVersion.items
        itemList.sort (a, b)-> a.compareTo b

        builder
            .line 'schema: ', 2
            .line 'name: ', modVersion.name
            .line 'version: ', modVersion.version
            .onlyIf modVersion.description?, => builder.line 'description: ', modVersion.description
            .line()
            .onlyIf itemList.length > 0, =>
                builder.loop itemList, delimiter:'\n', onEach:(b, i)=> @_unparseItem(b, i)
            .outdent()

    _unparseItem: (builder, item)->
        builder
            .line 'item: ', item.name
            .indent()
                .onlyIf item.isGatherable, => builder.line 'gatherable: yes'
                .onlyIf item.recipes.length > 0, =>
                    builder.loop item.recipes, delimiter:'', onEach:(b, r)=> @_unparseRecipe(b, r)
            .outdent()

    _unparseRecipe: (builder, recipe)->
        inputNames = (builder.context.findName(stack.slug) for stack in recipe.input)
        inputNames.sort()

        patternMap = {'.', '.'}
        for i in [0...recipe.input.length]
            stack = recipe.input[i]
            patternMap["#{i}"] = "#{inputNames.indexOf builder.context.findName(stack.slug)}"

        pattern = recipe.pattern or recipe.defaultPattern
        newPattern = []
        for c in pattern.split('')
            newPattern.push patternMap[c]
        newPattern = newPattern.join ''
        newPattern = newPattern.replace /(...)(...)(...)/, '$1 $2 $3'

        quantity = recipe.output[0].quantity

        extraOutputs = recipe.output[0...recipe.output.length]
        extraOutputs.shift()

        builder
            .line 'recipe:'
            .indent()
                .onlyIf extraOutputs.length > 0, =>
                    builder
                        .push 'extras: '
                        .call => @_unparseStackList builder, extraOutputs
                        .line()
                .push 'input: '
                    .loop inputNames
                    .line()
                .line 'pattern: ', newPattern
                .onlyIf quantity > 1, => builder.line 'quantity: ', quantity
                .onlyIf recipe.tools.length > 0, =>
                    builder
                        .push 'tools: '
                        .call => @_unparseStackList builder, recipe.tools
                        .line()
            .outdent()

    _unparseStackList: (builder, stackList)->
        if stackList.length is 1 and stackList[0].quantity is 1
            builder.push builder.context.findName(stackList[0].slug)
        else
            builder.loop stackList, onEach:(b, stack)=>
                builder
                    .onlyIf stack.quantity > 1, => builder.push stack.quantity, ' '
                    .push builder.context.findName stack.slug
