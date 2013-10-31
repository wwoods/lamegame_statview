define [ 'cs!statPath', 'cs!stat', 'cs!eventsController' ], (StatPath, Stat, EventsController) ->
    class StatsController
        constructor: (availableStats) ->
            @availableStats = availableStats
            @availableStats_doc = """List of stats that are available"""

            @stats = {}
            @stats_doc = """{ name: { path: path w/ groups, groups: [ group names ] } }"""
            @groups = {}
            @groups_doc = """{ name: [ sorted possible values ] }"""
            @statPaths = []
            @events = new EventsController()


        parseStats: (paths) ->
            ### Re-parse our availableStats list, using paths.
            ###
            @stats = {}
            # { statName : [ [ targetPath, groupValue1, groupValue2, ... ] ] }
            @statToTarget = {}
            @usedStats = {}
            @inactiveStats = {}
            @groups = {}
            @statPaths = []
            
            for path in paths
                @_addPath(path)
                                    
            for stat in @availableStats
                bestResult = null
                bestPath = null
                for path in @statPaths
                    result = path.matchStat(stat)
                    if result == null
                        continue
                    if not bestResult? or bestResult.score < result.score
                        bestResult = result
                        bestPath = path
                
                if bestResult == null
                    # No matches
                    continue
                result = bestResult
                path = bestPath
                    
                # It's a match, but is this path inactive?
                if result.inactive
                    @inactiveStats[stat] = true
                    continue
                    
                # We are using this stat, so add it to allStats so that
                # we can actually load it
                @usedStats[stat] = true
                targetArray = [ stat ]
                for group in result.groups
                    targetArray.push(group[1])

                if result.name not of @statToTarget
                    @statToTarget[result.name] = [ targetArray ]
                else
                    @statToTarget[result.name].push(targetArray)

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
                        result.name += ".BROKEN.EXAMPLE"
                        alert("Same stat, different properties; see console")
                        @stats[result.name] = statDef
                else
                    @stats[result.name] = statDef
                        
            for g of @groups
                @groups[g].sort()


        setAliases: (aliases) ->
            @aliases = {}
            for def in aliases
                @aliases[def.id] = def.aliases


        _addPath: (pathOptions) ->
            if typeof pathOptions == 'string'
                statPath = new StatPath(path: pathOptions)
            else if not (pathOptions instanceof StatPath)
                if not pathOptions.path
                    # An error row
                    return
                statPath = new StatPath(pathOptions)
            @statPaths.push(statPath)


