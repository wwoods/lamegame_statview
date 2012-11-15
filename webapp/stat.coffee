define [], (Stat) ->
    class Stat
        constructor: (params) ->
            # type = 'count' or 'total'
            @name = params.name
            @groups = params.groups
            @path = params.path
            @pathRegex = params.pathRegex
            @type = params.type
            if not @type?
                @type = 'count'
                if /-sample$/.test(@path)
                    @type = 'total'


        getTarget: (groupValues) ->
            ###groupValues: { group : value }
            Returns a graphite-suitable target path with *'s
            ###
            target = @path
            for group in @groups
                toReplace = '{' + group + '}'
                value = '*'
                if group of groupValues
                    value = groupValues[group]
                target = target.replace(toReplace, value)

            if true
                # We're using graphite, no need
            else if @type == 'count'
                ntarget = 'aliasSub(aliasSub(transformNull(sumSeries('
                ntarget += target
                ntarget += '), 0), ".*sumSeries\\(", ""), "\\).*", "")'
                target = ntarget
            else if @type == 'total'
                target = 'blah'
            else
                throw 'Unknown type ' + @type
            return target


        matchPath: (path) ->
            # Returns null if this stat does not match path, or returns a dict
            # of { group : value }
            match = @pathRegex.exec(path)
            # Reset regex
            @pathRegex.lastIndex = 0

            result = null
            if match
                result = {}
                for group, i in @groups
                    # Just like in statPath, every other group is our actual
                    # group
                    result[group] = match[2*(i + 1)]
            return result

    
