define [], (Stat) ->
    class Stat
        constructor: (params) ->
            # type = 'count' or 'total' or 'total-max'
            @name = params.name
            @groups = params.groups
            @path = params.path
            @pathRegex = params.pathRegex
            @type = params.type
            @score = params.score
            if not @type?
                @type = 'count'
                if /-sample$/.test(@path)
                    @type = 'total'


        getTarget: (groupValues) ->
            ###groupValues: { group : value }
            Returns a target path with *'s for groups that are unspecified
            ###
            if not @_targetParts
                @_initTargetParts()

            target = []
            for tp in @_targetParts
                if typeof tp == 'string'
                    target.push(tp)
                else
                    value = '*'
                    group = @groups[tp]
                    if group of groupValues
                        value = groupValues[group]
                    target.push(value)
            return target.join('')


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


        _initTargetParts: () ->
            # String or index into @groups.
            @_targetParts = []
            pathIter = /\{/g

            lastSpotEnd = -1
            # Remember - regex lastIndex is 1 greater than the char index.
            while (m = pathIter.exec(@path)) != null
                # spot - open bracket position
                spot = pathIter.lastIndex - 1
                if spot > lastSpotEnd + 1
                    @_targetParts.push(@path[lastSpotEnd + 1...spot])

                spotEnd = /\}/g
                spotEnd.lastIndex = spot + 1
                spotEndMatch = spotEnd.exec(@path)
                lastSpotEnd = spotEnd.lastIndex - 1
                pathIter.lastIndex = lastSpotEnd + 2
                spotGroup = @path[spot + 1...lastSpotEnd]

                matched = false
                for group, i in @groups
                    if spotGroup == group
                        @_targetParts.push(i)
                        matched = true
                        break
                if not matched
                    console.log("Unmatched group #{ spotGroup } of #{ @name }")
                    @_targetParts.push("UM:" + spotGroup)
            @_targetParts.push(@path[lastSpotEnd + 1..])
