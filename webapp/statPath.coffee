define [], () ->
    class StatPath
        constructor: (pathOptions) ->
            @options = pathOptions
            # TODO - Stats should get options from specific members of @options
            @statOptions =
                type: if @options.type then @options.type else 'count'
            path = @options.path

            # Find groups in our path
            @groups = []
            findGroup = /{([^}]*)}/g
            next = null
            while (next = findGroup.exec(path)) != null
                @groups.push(next[1])

            @path = path
            type = 'stat'
            if /\.\*$/.test(@path)
                type = 'dir'
                @path = @path[0...-2]
            else if /\.\*\*$/.test(@path)
                type = 'superdir'
                @path = @path[0...-3]
            @type = type
            @pathRegex = @getRegexForPath(@path, @type)


        getRegexForPath: (path, type = "stat") ->
            # Return a regex that matches the given path and type
            # Note that, in order to perfectly find where our matched groups
            # are, we need to have each individual segment of the regex in
            # a capturing group.
            findGroup = /{([^}]*)}/g
            reString = (
                    '^' + path.replace(/\./g, '\\.')
                            .replace(findGroup, '([^\\.]*)')
            )
            
            # Extra note - we're tricky.  We insert a group in between each
            # actually wanted capturing group, meaning that the odd-indexed
            # captures are our actual groups.
            lastParenEnd = -1
            while (nextParen = reString.indexOf('(', lastParenEnd)) >= 0
                reString = reString[...lastParenEnd + 1] + '(' +
                        reString[lastParenEnd + 1...nextParen] + ')' +
                        reString[nextParen..]
                # And we've added two chars, so..
                lastParenEnd = reString.indexOf(')', nextParen + 2)
                if lastParenEnd < 0
                    throw "Bad regex: " + reString
            # From lastParenEnd to end is final capture group
            reString = reString[...lastParenEnd + 1] + '(' + 
                    reString[lastParenEnd + 1..]
            if type == 'dir'
                reString += '\\.[^\\.]*'
            else if type == 'superdir'
                reString += '\\..*'

            # Close out regex and make sure it's a complete match
            reString += ')$'
            return new RegExp(reString, 'g')


        matchStat: (path) ->
            # See if the given path matches our StatPath... if it does, return
            # a dict to initialize a Stat:
            # { name: 'statName', groups: [ [ 'group', 'value' ] ],
            #       path: 'myPathWithName', pathRegex: 'regexForStat' }
            # Otherwise returns null.
            stat = null
            result =
                name: null
                groups: []
                path: null

            match = @pathRegex.exec(path)
            # Reset regex so that exec works next time
            @pathRegex.lastIndex = 0
            if match == null
                return match

            for group, i in @groups
                # Remember, we put capture groups between the groups we
                # care about, so even indices are group values
                result.groups.push([ group, match[2 * (i + 1)] ])

            statName = '' # construct stat name from odd captured groups
            for i in [1...match.length]
                if i % 2 == 0
                    continue
                statName += match[i]
            
            # Make it pretty - take out double or more dots, since they're 
            # leftovers from filtered groups
            statName = statName.replace(/\.\.+/g, '.')

            result.name = statName
            if @type == 'dir' or @type == 'superdir'
                statPart = result.name[result.name.lastIndexOf('.') + 1 ..]
                result.path = @path + '.' + statPart
            else
                result.path = @path
            result.pathRegex = @getRegexForPath(result.path)
            return result



