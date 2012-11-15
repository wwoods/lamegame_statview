define [], () ->
    class StatPath
        constructor: (pathOptions) ->
            @options = pathOptions
            # TODO - Stats should get options from specific members of @options
            @statOptions = undefined
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
            findGroup = /{([^}]*)}/g
            reString = (
                    '^' + path.replace(/\./g, '\\.')
                            .replace(findGroup, '([^\\.]*)')
            )
            if type == 'dir'
                reString += '\\.[^\\.]*$'
            else if type == 'superdir'
                reString += '\\..*$'
            else
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
                result.groups.push([ group, match[i + 1] ])

            name = match[0]
            for i in [1..@groups.length]
                toReplace = match[i]
                if i == 1 and @path[0] == '{'
                    toReplace += '.'
                else
                    toReplace = '.' + toReplace

                # Javascript string replace only replaces first instance, which
                # is exactly what we want
                name = name.replace(toReplace, '')

            result.name = name
            if @isDir
                statPart = result.name[result.name.lastIndexOf('.') + 1 ..]
                result.path = @path + '.' + statPart
            else
                result.path = @path
            result.pathRegex = @getRegexForPath(result.path)
            return result



