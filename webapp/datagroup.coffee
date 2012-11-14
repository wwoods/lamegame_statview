define ["cs!dataset"], (DataSet) ->
    class DataGroup
        ### A DataGroup represents an aggregation level, and stores both
        subgroups that may be drilled into and the value of stats at that
        aggregation level.
        
        Also computes value of a graph's expression at each point.
        ###
        
        constructor: (title, computeOptions) ->
            @title = title
            @computeOptions = computeOptions
            @values = {}
            @subgroups = {}
            
            
        getGraphPoints: () ->
            ### Compute the actual DataSet to pass to d3 for our expression
            across this dataGroup and return it
            ###
            if @__expr__?
                # Already calculated
                return @__expr__
                
            # Decompress computeOptions
            stats = @computeOptions.stats
            pointTimes = @computeOptions.pointTimes
            exprFn = @computeOptions.fn
            
            exprVals = new DataSet(@, @title)
            dgVals = @values
            for j in [0...dgVals[stats[0].name].length]
                ctx = {}
                for s, q in stats
                    vals = dgVals[s.name]
                    ctx['v' + q] = vals[j]
                result = exprFn(ctx)
                exprVals.push(
                    x: pointTimes[j]
                    y: result
                )
                
            # Cache and return
            @__expr__ = exprVals
            
            