define [], () ->
    class StatPath
        constructor: (path, statOptions) ->
            @statOptions = statOptions

            # Find groups in our path
            @groups = []
            findGroup = /{([^}]*)}/g
            next = null
            while (next = findGroup.exec(path)) != null
                @groups.push(next[1])

            @path = path
            isDir = false
            if /\.\*$/.test(@path)
                isDir = true
                @path = @path[0...-2]
            @isDir = isDir
            @pathRegex = @getRegexForPath(@path, @isDir)


        getRegexForPath: (path, isDir) ->
            # Return a regex that matches the given path
            findGroup = /{([^}]*)}/g
            reString = (
                    '^' + path.replace('.', '\\.')
                            .replace(findGroup, '([^\\.]*)')
            )
            if isDir
                reString += '\\.[^\\.]*'
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



