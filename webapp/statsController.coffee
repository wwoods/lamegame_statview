define [ 'cs!statPath', 'cs!stat' ], (StatPath, Stat) ->
    class StatsController
        constructor: () ->
            @stats = {}
            @stats_doc = """{ name: { path: path w/ groups, groups: [ group names ] } }"""
            @groups = {}
            @groups_doc = """{ name: [ possible values ] }"""
            @statPaths = []


        addStats: (statPath, statOptions) ->
            if typeof statPath == 'string'
                statPath = new StatPath(statPath, statOptions)
            @statPaths.push(statPath)


        parseStats: (stats) ->
            @allStats = {}
            for stat in stats
                @allStats[stat] = true
                for path in @statPaths
                    result = path.matchStat(stat)
                    if result == null
                        continue

                    statInit =
                        name: result.name
                        path: result.path
                        pathRegex: result.pathRegex
                        groups: []
                    $.extend(statInit, path.statOptions)

                    statDef = new Stat(statInit)
                    # Add each group to the stat, and also any values that
                    # we're missing to our record of possible values for that
                    # group
                    for group in result.groups
                        statDef.groups.push(group[0])
                        if not (group[0] of @groups)
                            @groups[group[0]] = []
                        if $.inArray(group[1], @groups[group[0]]) < 0
                            @groups[group[0]].push(group[1])

                    if result.name of @stats
                        if not $.compareObjs(statDef, @stats[result.name])
                            console.log("Showing new def, then old def")
                            console.log(statDef)
                            console.log(@stats[result.name])
                            throw "Same stat, different properties"
                    else
                        @stats[result.name] = statDef


