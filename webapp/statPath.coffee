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
            @pathRegex = @getRegexForPath(@path)
            
            # Calculate the score for our path; more specific chars means
            # a higher score
            @score = path.replace(/\*/g, '').replace(/{([^}]*)}/g, '').length


        getRegexForPath: (path) ->
            # Return a regex that matches the given path, after wildcard (* and
            # **) substitutions.
            # Note that, in order to perfectly find where our matched groups
            # are, we need to have each individual segment of the regex in
            # a capturing group.
            findDoubleStar = /\*\*/g
            findStar = /\*/g
            findGroup = /{([^}]*)}/g
            reString = (
                    '^' + path.replace(/\./g, '\\.')
                            .replace(findDoubleStar, '.+')
                            .replace(findStar, '.*')
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
            # From lastParenEnd to end is final specified capture group
            reString = reString[...lastParenEnd + 1] + '(' + 
                    reString[lastParenEnd + 1..] + ')'

            # Close out regex and make sure it's a complete match
            reString += '$'
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
            statPath = '' # Build stat path at same time, replacing captured
                          # groups with the group name
            statPathGroupsLeft = @groups[..]
            for i in [1...match.length]
                if i % 2 == 0
                    statPath += '{' + statPathGroupsLeft.shift() + '}'
                    continue
                statName += match[i]
                statPath += match[i]
                
            # We score matches according to longest specified match.  That is,
            # the most non-group and non-wildcard characters
            result.score = @score
            
            # Make it pretty - take out double or more dots, since they're 
            # leftovers from filtered groups
            statName = statName.replace(/\.\.+/g, '.')
            # Also trim some leading or trailing chars, since, while they are 
            # valid in a path name, they are indistinguishable with subtraction
            # if we allow them at the end, which may be confusing (and isn't
            # pretty; normally there will be a dash at the end because a group
            # is only part of the name).
            statName = statName.replace(/[\.-]+$/, '').replace(/^[\.-]+/, '')

            result.name = statName
            result.path = statPath
            result.pathRegex = @getRegexForPath(result.path)
            
            if @options.inactive
                result.inactive = true
            
            return result



