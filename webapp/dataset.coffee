define [], () ->
    class DataSet extends Array
        ### A DataSet represents an array of information that we pass to d3.
        ###
        constructor: (group, title) ->
            ### A DataSet represents point information from a DataGroup.
            ###
            
            super()
            @group = group
            @title = title
            @subsets = []
            
            
        addSubset: (dataSet) ->
            dataSet.title = @title + ' - ' + dataSet.title
            @subsets.push(dataSet)
            
            
        getBounds: () ->
            ### Return a dict with xmin, xmax, ymin, and ymax, that correspond
            to the extremes in our data.
            ###
            xmin = 1e35
            xmax = -1e35
            ymin = 1e35
            ymax = -1e35
            for pt in @
                xmin = Math.min(pt.x, xmin)
                ymin = Math.min(pt.y, ymin)
                xmax = Math.max(pt.x, xmax)
                ymax = Math.max(pt.y, ymax)
            return {
                xmin: xmin
                xmax: xmax
                ymin: ymin
                ymax: ymax
            }
            