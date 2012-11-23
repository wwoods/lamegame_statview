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
            expression = @computeOptions.expr

            numPts = @values[stats[0].name][0].length
            
            exprVals = new DataSet(@, @title)
            expression.eval(exprVals, @values, 
                    @computeOptions.statsController, pointTimes)
                
            # Cache and return
            @__expr__ = exprVals
            
            
