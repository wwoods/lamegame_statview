define ["cs!dataset"], (DataSet) ->
    class DataGroup
        ### A DataGroup represents an aggregation level, and stores both
        subgroups that may be drilled into and the value of stats at that
        aggregation level.
        
        Also computes value of a graph's expression at each point.
        ###
        
        constructor: (title, computeOptions, @parent = null) ->
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
            expression = @computeOptions.expr

            # Some stats may not be aggregated at a parent level, so we'll
            # just use the parent's value.
            values = {}
            for stat, data of @values
                values[stat] = data
            p = @parent
            while p?
                for stat, data of p.values
                    if stat not of values
                        values[stat] = data
                p = p.parent

            # All data sets at this point have the same length, so find the
            # first valid one and 
            numPts = 0
            for statName, dataSets of values
                if dataSets.length > 0
                    numPts = dataSets[0].length
                    break
            
            exprVals = new DataSet(@, @title)
            expression.eval(exprVals, values, 
                    @computeOptions.statsController, pointTimes)
                
            # Cache and return
            @__expr__ = exprVals
            
            
