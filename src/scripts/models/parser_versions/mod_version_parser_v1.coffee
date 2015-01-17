###
Crafting Guide - mod_version_parser_v1.coffee

Copyright (c) 2014-2015 by Redwood Labs
All rights reserved.
###

Item       = require '../item'
ModVersion = require '../mod_version'
Recipe     = require '../recipe'
Stack      = require '../stack'

########################################################################################################################

module.exports = class ModVersionParserV1

    constructor: (options={})->
        if not options.model? then throw new Error 'options.model is required'
        @_model         = options.model
        @_errorLocation = 'the header information'

    parse: (data)->
        return @_parseModVersion data

    unparse: ->
        return @_unparseModVersion()

    # Private Methods ##############################################################################

    _computeDefaultPattern: (input)->
        itemCount = input.length
        slotCount = _.reduce input, ((total, stack)-> total + stack.quantity), 0

        return '... .0. ...' if itemCount is 1 and slotCount is 1
        return '00. 00. ...' if itemCount is 1 and slotCount is 4
        return '000 000 000' if itemCount is 1 and slotCount is 9

        result = ['.', '.', '.', '.', '.', '.', '.', '.', '.']
        indexes = [4, 7, 1, 3, 5, 6, 8, 0, 2]

        for i in [0...input.length]
            stack = input[i]
            for j in [0...stack.quantity]
                index = indexes.shift()
                result[index] = "#{i}"

        pattern = result.join ''
        pattern = pattern.replace /(...)(...)(...)/, '$1 $2 $3'
        return pattern

    _findOrCreateItem: (name)->
        item = @_model.findItemByName name
        if not item?
            item = new Item name:name
            @_model.addItem item
        return item

    # Parsing Methods ##############################################################################

    _parseModVersion: (data)->
        if not data? then throw new Error 'mod description data is missing'
        if not data.name? then throw new Error 'name is required'
        if not data.version? then throw new Error 'version is required'
        if not _.isArray(data.recipes) then throw new Error 'recipes must be an array'

        if data.name isnt @_model.name
            throw new Error "the data is for #{data.name}, not #{@_model.name} as expected"
        if data.version isnt @_model.version
            throw new Error "the data is for version #{data.version}, not #{@_model.version} as expected"

        @_model.description = data.description or ''
        @_parseRawMaterials data.raw_materials

        for index in [0...data.recipes.length]
            @_errorLocation = "recipe #{index + 1}"
            recipeData = data.recipes[index]
            recipe = @_parseRecipe recipeData
            recipe._originalIndex = index

        return @_model

    _parseRawMaterials: (data)->
        return unless data? and data.length > 0

        results = []
        for name in data
            item = @_findOrCreateItem name
            item.isGatherable = true
            results.push item

    _parseRecipe: (data)->
        if not data? then throw new Error "recipe data is missing for #{@_errorLocation}"
        if not data.output? then throw new Error "#{@_errorLocation} is missing output"

        data.output = if _.isArray(data.output) then data.output else [data.output]
        names = (e for e in _.flatten(data.output) when _.isString(e))
        if names.length is 0 then throw new Error "#{@_errorLocation} has an empty output list"

        item = @_findOrCreateItem names[0]
        @_errorLocation = "recipe for #{item.name}"

        if not data.input? then throw new Error "#{@_errorLocation} is missing input"
        data.tools ?= []

        attributes =
            item:   item,
            output: @_parseStackList(data.output, field:'output', canBeEmpty:false)
            input:  @_parseStackList(data.input,  field:'input',  canBeEmpty:true)
            tools:  @_parseStackList(data.tools,  field:'tools',  canBeEmpty:true)
        attributes.pattern = data.pattern or @_computeDefaultPattern attributes.input

        recipe = new Recipe attributes
        return recipe

    _parseStack: (data, options={})->
        errorBase = "#{options.field} element #{options.index} for #{@_errorLocation}"
        if not data? then throw new Error "#{errorBase} is missing"

        if _.isString(data) then data = [1, data]
        if not _.isArray(data) then throw new Error "#{errorBase} must be an array"

        if data.length is 1 then data.unshift 1
        if data.length isnt 2 then throw new Error "#{errorBase} must have at least one element"
        if not _.isNumber(data[0]) then throw new Error "#{errorBase} must start with a number"

        name = data[1]
        slug = _.slugify name
        @_model.registerSlug slug, name

        return new Stack slug:slug, quantity:data[0]

    _parseStackList: (data, options={})->
        if not data? then throw new Error "#{@_errorLocation} must have an #{options.field} field"

        if not _.isArray(data) then data = [data]
        if data.length is 0 and not options.canBeEmpty
            throw new Error "#{options.field} for #{@_errorLocation} cannot be empty"

        result = []
        for index in [0...data.length]
            stackData = data[index]
            result.push @_parseStack stackData, field:options.field, index:index

        return result

    # Un-parsing Methods ###########################################################################

    _unparseModVersion: (modVersion)->
        result = []
        result.push '{\n'
        result.push '    "dataVersion": 1,\n'
        result.push '    "name": "' + modVersion.name + '",\n'
        result.push '    "version": "' + modVersion.version + '",\n'
        if modVersion.description.length > 0
            result.push '    "description": "' + modVersion.description + '",\n'

        rawMaterials = (item.name for slug, item of modVersion.items when item.isGatherable)
        rawMaterials.sort()
        if rawMaterials.length > 0
            result.push '    "raw_materials": [\n'
            firstItem = true
            for material in rawMaterials
                if not firstItem then result.push ',\n'
                result.push '        "' + material + '"'
                firstItem = false
            result.push '\n    ],\n'

        result.push '    "recipes": [\n'

        items = (item for slug, item of modVersion.items when item.isCraftable)
        items.sort (a, b)-> a.compareTo b

        firstItem = true
        for item in items
            for recipe in item.recipes
                result.push if firstItem then '        {\n' else '        }, {\n'
                @_unparseRecipe recipe, result
                firstItem = false
        result.push '        }\n'

        result.push '    ]\n'
        result.push '}'

        return result.join ''

    _unparseRecipe: (recipe, result=[])->
        result.push '            "output": '
        @_unparseStackList recipe.output, result, sort:false

        if recipe.input.length > 0
            result.push ',\n'
            result.push '            "input": '
            @_unparseStackList recipe.input, result

        if recipe.pattern?
            result.push ',\n'
            result.push '            "pattern": "'
            result.push recipe.pattern
            result.push '"'

        if recipe.tools.length > 0
            result.push ',\n'
            result.push '            "tools": '
            @_unparseStackList recipe.tools, result

        result.push '\n'
        return result

    _unparseStackList: (stackList, result, options={})->
        options.sort ?= true

        if stackList.length is 0
            result.push '[]'
        else if stackList.length is 1
            stack = stackList[0]
            if stack.quantity is 1
                result.push '"' + @_model.findName(stack.slug) + '"'
            else
                result.push '[[' + stack.quantity + ', "' + @_model.findName(stack.slug) + '"]]'
        else
            result.push '['

            stacks = stackList.slice()
            if options.sort
                stacks.sort (a, b)->
                    if a.quantity isnt b.quantity
                        return if a.quantity > b.quantity then -1 else +1
                    if a.slug isnt b.slug
                        return if a.slug < b.slug then -1 else +1
                    return 0

            firstItem = true
            for stack in stacks
                result.push ', ' if not firstItem
                if stack.quantity is 1
                    result.push '"' + @_model.findName(stack.slug) + '"'
                else
                    result.push '[' + stack.quantity + ', "' + @_model.findName(stack.slug) + '"]'
                firstItem = false

            result.push ']'

        return result
