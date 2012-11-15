define [ 'cs!statPath', 'cs!stat' ], (StatPath, Stat) ->
    class StatsController
        constructor: (availableStats) ->
            @availableStats = availableStats
            @availableStats_doc = """List of stats that are available"""

            @stats = {}
            @stats_doc = """{ name: { path: path w/ groups, groups: [ group names ] } }"""
            @groups = {}
            @groups_doc = """{ name: [ possible values ] }"""
            @statPaths = []


        parseStats: (paths) ->
            ### Re-parse our availableStats list, using paths.
            ###
            @usedStats = {}
            @inactiveStats = {}
            @groups = {}
            @statPaths = []
            
            for path in paths
                @_addPath(path)
                                    
            for stat in @availableStats
                for path in @statPaths
                    result = path.matchStat(stat)
                    if result == null
                        continue
                        
                    # It's a match, but is this path inactive?
                    if path.options.inactive
                        @inactiveStats[stat] = true
                        break
                        
                    # We are using this stat, so add it to allStats so that
                    # we can actually load it
                    @usedStats[stat] = true

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


        _addPath: (pathOptions) ->
            if typeof pathOptions == 'string'
                statPath = new StatPath(path: pathOptions)
            else if not (pathOptions instanceof StatPath)
                if not pathOptions.path
                    # An error row
                    return
                statPath = new StatPath(pathOptions)
            @statPaths.push(statPath)


