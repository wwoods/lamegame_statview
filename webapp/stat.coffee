define [], (Stat) ->
    class Stat
        constructor: (params) ->
            # type = 'count' or 'total' or 'total-max'
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
            Returns a target path with *'s for groups that are unspecified
            ###
            target = @path
            for group in @groups
                toReplace = '{' + group + '}'
                value = '*'
                if group of groupValues
                    value = groupValues[group]
                target = target.replace(toReplace, value)
                
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
                    # Chrome (at least) memory management uses a complicated
                    # set of operations to not duplicate memory for substring
                    # operations.  However, we truly want to copy the string
                    # so that we don't keep the massive data string around.
                    # So, copy it via a hack.
                    result[group] = match[2*(i + 1)].replace(/./, "$&")
            return result

    
