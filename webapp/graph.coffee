reqs = [ 'cs!lib/ui', 'cs!stat', 'cs!controls', 'cs!dataset', 'cs!datagroup',
        'css!graph' ]
module = (ui, Stat, Controls, DataSet, DataGroup) ->
    class Graph extends ui.Base
        constructor: (config) ->
            super('<div class="graph"></div>')
            self = this
            self._statsController = ui.Base.fromDom('.stats-app')._statsController

            self._display = $('<div class="graph-display"></div>').appendTo(
                    self)

            self.config =
                title: '(unnamed)'
                type: 'area-zoom'
                expr: ''
                # List of (groupName, filterRegex) to break down results. 
                # filterRegex is the text, and may be empty string for none
                groups: []
                # Time to sum data over for each point (expression passed
                # to parseInterval)
                smoothOver: ''
                # Expression (passed to parseInterval).  Use blank string to
                # use dashboard value
                timeAmt: ''
                # String relating time to start or empty for dashboard
                timeBasis: ''
                # Seconds between auto refresh, or '' to use dashboard
                autoRefresh: ''
                # Points to display on the graph
                graphPoints: 300
            if config
                $.extend(self.config, config)
            self._autoRefreshTimeout = null
            self._authRefreshNext = null

            expanded = not config?
            self._controls = new Controls(self, expanded).appendTo(self)
            self._overlay = $('<div class="graph-overlay"></div>').appendTo(@)
            self._loadingOverlay = $('<div class="graph-loading-overlay">
                    </div>').appendTo(@_overlay)

            # Render once we're attached to dashboard
            ui.setZeroTimeout () =>
                self.update()


        parseInterval: (interval, defaultInterval = 60*60) ->
            if interval == ''
                return 0

            if /d(y|ay)?s?$/.test(interval)
                #Days
                return parseFloat(interval) * 24 * 60 * 60
            else if /m(in|inute)?s?$/.test(interval)
                #Minutes
                return parseFloat(interval) * 60
            else if /h(ou)?r?s?$/.test(interval)
                # Hours
                return parseFloat(interval) * 60 * 60
            else if /w(ee)?k?s?$/.test(interval)
                # Weeks
                return parseFloat(interval) * 7 * 24 * 60 * 60
            else if /\d+$/.test(interval)
                # default
                return parseFloat(interval) * defaultInterval
            else
                throw "Invalid interval: " + interval


        parseStats: (expr) ->
            ### Parse an expression for stats, return array of stats used
            ###
            statsFound = []
            findStat = /[a-zA-Z0-9_.-]+/g
            while (next = findStat.exec(expr)) != null
                stat = @_statsController.stats[next[0]]
                if not stat
                    continue

                statsFound.push(stat)
            return statsFound


        update: (configChanges) ->
            self = this
            if configChanges
                for q of configChanges
                    if not $.compareObjs(self.config[q], configChanges[q])
                        # Something actually changed
                        self.trigger("needs-save")
                        break
                $.extend(self.config, configChanges)
            
            # Clear out old autorefresh
            if self._autoRefreshTimeout != null
                clearTimeout(self._autoRefreshTimeout)
                self._autoRefreshTimeout = null

            if self.config.expr == null or self.config.expr == ''
                self._display.empty()
                self._loadingOverlay.text('(No data selected)')
                return

            # Set up title and loading stuff
            self._loadingOverlay.text('(Loading data, please wait)')

            # Set new autorefresh
            if self.config.autoRefresh > 0
                self._autoRefreshNext = (new Date().getTime() / 1000)
                self._autoRefreshNext += self.config.autoRefresh
            else
                self._autoRefreshNext = null

            stats = self.parseStats(self.config.expr)

            # Copy the groups array
            groups = self.config.groups[..]
            groupFiltersBase = self._statsController.groups

            groupFilters = {}
            for group in groups
                baseValues = groupFiltersBase[group[0]]
                if group[1] != ''
                    regex = new RegExp(group[1])
                    groupValues = []
                    groupFilters[group[0]] = groupValues
                    for j of baseValues
                        if regex.test(j)
                            groupValues.push(j)
                else
                    groupFilters[group[0]] = baseValues

            # Get all groups from all stats
            allGroups = {}
            for stat in stats
                for group in stat.groups
                    allGroups[group] = true

            # We don't support * syntax outbound; fill in all possible values
            # that aren't already specified
            for group of allGroups
                if not (group of groupFilters)
                    groups.push([ group ])
                    groupFilters[group] = groupFiltersBase[group]

            targetSet = {}
            self._iterateTargets(targetSet, stats, {}, groups, 0, groupFilters)
            targets = []
            for t of targetSet
                targets.push(t)

            timeTo = self.config.timeBasis
            if timeTo == ''
                timeTo = ui.fromDom(@closest('.dashboard')).getTimeBasis()
            if timeTo == 'now'
                timeTo = (new Date().getTime() / 1000)

            timeAmt = self.config.timeAmt
            if timeAmt == ''
                timeAmt = ui.fromDom(@closest('.dashboard')).getTimeAmt()
            timeFrom = timeTo - self.parseInterval(timeAmt)

            $.ajax('getData', {
                type: 'POST'
                data: {
                    targetListJson: JSON.stringify(targets)
                    timeFrom: Math.floor(timeFrom - self.parseInterval(
                            self.config.smoothOver))
                    timeTo: Math.floor(timeTo)
                }
                success: (data) -> self._onLoaded(data, timeFrom, timeTo, stats)
                error: () -> self._loadingOverlay.text('(Failed to load)')
            })


        _aggregateSourceData: (rawData, pointTimes, timeFrom) ->
            # Searches our statsController's stats for the stat matching
            # rawLine, and aggregates it appropriately according to the stat
            # type
            #
            # rawData - As per graphite's "raw" output:
            # statName, timestampFirst, timestampDelta, data...
            #
            # Returns a dict:
            # { stat: statName, groups: { group : value },
            #       values: [ array of values applicable at pointTimes ] }
            self = this

            matchStat = null
            matchGroups = null
            for statName of self._statsController.stats
                stat = self._statsController.stats[statName]
                match = stat.matchPath(rawData[0])
                if match != null
                    matchStat = stat
                    matchGroups = match
                    break

            if matchStat == null
                throw "Could not match stat: " + rawData[0]

            result = { stat: matchStat, groups: matchGroups }
            values = []
            result.values = values
            
            # First thing's first - if we're a total, we need to replace all
            # 'None' values with the last value.  If we're a count, just
            # replace all 'None' values with 0.
            if stat.type == 'total'
                lastValue = 0;
                for i in [4...rawData.length]
                    if rawData[i] != 'None'
                        lastValue = rawData[i]
                    else
                        rawData[i] = lastValue
            else if stat.type == 'count'
                for i in [4...rawData.length]
                    if rawData[i] == 'None'
                        rawData[i] = 0

            firstTime = timeFrom
            # Don't add any post-smoothing points before timeFrom, since for
            # smoothing we had to request more data than we needed.
            # Note that srcIndex and srcTime are actually the index of the NEXT
            # point to use
            srcIndex = 4
            srcInterval = parseInt(rawData[3])
            srcTime = parseInt(rawData[1]) # beginning of point, not end
            srcTimeBase = srcTime

            # Note that philosophically we consider the time in each pointTimes
            # record to be from immediately after the last point time up to and
            # including the next pointTime.
            smoothSecs = self.parseInterval(self.config.smoothOver)
            # Keep track of originally requested smoothing so that constants
            # affect the post-aggregated result of equations
            origSmooth = smoothSecs
            if smoothSecs < srcInterval
                # If no smoothing was specified, use the data density
                smoothSecs = srcInterval
            if smoothSecs < pointTimes[1] - pointTimes[0]
                # If smoothing was too small for between points, use point density
                smoothSecs = pointTimes[1] - pointTimes[0]
            #console.log("Final smooth: " + smoothSecs)

            movingTotal = 0.0
            movingIndex = srcIndex

            # We've removed up to this point of current point
            movingTime = srcTime
            # The start of current point
            movingTimeBase = movingTime

            for pointTime in pointTimes
                # We're actually going to compute a moving sum of partial data
                # points - that is, we assume our samples are uniformly
                # distributed between the two points they represent (dataTime
                # through dataTime + srcInterval, exclusive on the latter bound).
                # By doing this, we avoid awkward discrete computations that
                # can really cause errors in certain situations (e.g. those with
                # specific smoothing intervals)
                newTail = pointTime - smoothSecs
                while movingTime < newTail
                    # Take off of moving summation
                    timeLeft = newTail - movingTime
                    partLeft = movingTimeBase + srcInterval - movingTime

                    if stat.type == 'count'
                        if timeLeft < partLeft
                            # Remove none of count's value until the data point
                            # is completely out of the window
                            movingTime = newTail
                        else
                            # Remove the whole value
                            movingTotal -= parseFloat(rawData[movingIndex])
                            movingTime = movingTimeBase + srcInterval
                            movingTimeBase = movingTime
                            movingIndex += 1
                    else if stat.type == 'total'
                        if timeLeft >= partLeft
                            # Take off the whole rest of the point
                            movingTotal -= (
                                    parseFloat(rawData[movingIndex]) *
                                    partLeft / srcInterval)
                            movingTime = movingTimeBase + srcInterval
                            movingTimeBase = movingTime
                            movingIndex += 1
                        else
                            # Take off part of the point and we're done
                            movingTotal -= (
                                    parseFloat(rawData[movingIndex]) *
                                    timeLeft / srcInterval)
                            movingTime = newTail

                while srcIndex < rawData.length and srcTime < pointTime
                    # Moving summation
                    timeLeft = pointTime - srcTime
                    partLeft = srcTimeBase + srcInterval - srcTime

                    if stat.type == 'count'
                        # We want the first instance to count for everything
                        if srcTime == srcTimeBase
                            # We're at first point, add it
                            movingTotal += parseFloat(rawData[srcIndex])

                        # Are we going to a new point?
                        if timeLeft >= partLeft
                            srcTime = srcTimeBase + srcInterval
                            srcTimeBase = srcTime
                            srcIndex += 1
                        else
                            srcTime = pointTime
                    else if stat.type == 'total'
                        if timeLeft >= partLeft
                            # Rest of the point!
                            movingTotal += (
                                    parseFloat(rawData[srcIndex]) *
                                    partLeft / srcInterval)
                            srcTime = srcTimeBase + srcInterval
                            srcTimeBase = srcTime
                            srcIndex += 1
                        else
                            # Partial point and done
                            movingTotal += (parseFloat(rawData[srcIndex]) *
                                    timeLeft / srcInterval)
                            srcTime = pointTime

                # Now, add!
                if stat.type == 'count'
                    # For counts, if we wanted a smaller time range than
                    # the smoothing interval, we'll need to scale it down
                    if origSmooth != 0
                        values.push(movingTotal * origSmooth / smoothSecs)
                    else
                        # We want to use data density
                        values.push(movingTotal)
                else if stat.type == 'total'
                    # These are set values, so adjust smoothing according to
                    # the srcInterval
                    values.push(movingTotal * srcInterval / smoothSecs)
                else
                    throw "Stat type summation not defined: " + stat.type

            # Done!
            return result
        
        
        _drawAxis: (options) ->
            tickHeight = options.tickHeight
            pointTimes = options.pointTimes
            display = options.display

            width = display.width()
            height = display.height()

            xmin = pointTimes[0]
            xmax = pointTimes[pointTimes.length - 1]
            xcount = pointTimes.length
            intervalMax = xmax
            intervalLength = 60
            ticks = width / 40

            # Initially, intervalLength is minutes
            denoms = [
                # Note - try to keep diff between denoms around 3 or 4 to
                # make it less likely to have very few denoms.  Most be > 2
                # ALSO - Denoms < days MUST BE integer multiples
                # Minutes
                2
                5
                15
                30
                # Hours
                1*60
                4*60
                12*60
                # Days
                24*60
                2*24*60
                5*24*60
                15*24*60
                30*24*60
                90*24*60
            ]
            lastd = 1
            for d in denoms
                if (xmax - xmin) / intervalLength > ticks
                    intervalLength *= d / lastd
                    lastd = d
                else
                    break

            # Now that we have "optimal" length, align to nearest whole time 
            # unit
            intervalShift = 0
            maxDate = new Date()
            maxDate.setTime(xmax * 1000)
            minDate = new Date()
            minDate.setTime(xmin * 1000)

            timeToReset = [
                # Array of lambdas based off of maxDate to get the number of
                # seconds to take off to reach the next "round" tick
                () -> maxDate.getSeconds()
                () -> (maxDate.getMinutes() % 5) * 60
                () -> (maxDate.getMinutes() % 20) * 60
                () -> (maxDate.getMinutes() % 30) * 60
                () -> maxDate.getMinutes() * 60
                () -> (maxDate.getHours() % 2) * 60*60
                () -> (maxDate.getHours() % 6) * 60*60
                () -> maxDate.getHours() * 60*60
            ]

            for nextResetFn in timeToReset
                nextReset = nextResetFn()
                if intervalShift + nextReset < intervalLength * xcount
                    intervalShift += nextReset
                    maxDate.setTime((intervalMax - intervalShift) * 1000)
                else
                    break

            # Effect the interval
            intervalMax -= intervalShift
            if intervalShift > intervalLength
                # We've set back more than one interval, to align with a 
                # greater time period.  We need to add back missing intervals
                while intervalMax + intervalLength < xmax
                    intervalMax += intervalLength

            intervals = []
            while intervalMax > xmin
                d = new Date()
                d.setTime(intervalMax * 1000)
                
                # This fixes daylight savings, but also is kind of nice if an
                # exact day should happen to fall between two intervals
                leftInDay = d.getHours() * 60 * 60 + d.getMinutes() * 60
                if intervalLength > leftInDay
                	intervalMax -= leftInDay
                	d.setTime(intervalMax * 1000)

                if d.getHours() == 0 and d.getMinutes() == 0
                    # Month : day timestamps
                    months =
                        0: 'Jan'
                        1: 'Feb'
                        2: 'Mar'
                        3: 'Apr'
                        4: 'May'
                        5: 'Jun'
                        6: 'Jul'
                        7: 'Aug'
                        8: 'Sep'
                        9: 'Oct'
                        10: 'Nov'
                        11: 'Dec'
                    label = months[d.getMonth()] + d.getDate().toString()
                else
                    # Hour : Minute timestamps
                    hrs = d.getHours().toString()
                    if hrs.length < 2
                        hrs = '0' + hrs
                    mins = d.getMinutes().toString()
                    if mins.length < 2
                        mins = '0' + mins
                    label = hrs + ':' + mins

                intervals.push(
                    x: (intervalMax - xmin) * width / (xmax - xmin)
                    label: label 
                )

                intervalMax -= intervalLength

            axis = d3.select(display[0])
                .append('svg')
            $(axis[0]).css
                position: 'absolute'
                bottom: 0
                left: 0
            axis
                .attr('width', width).attr('height', tickHeight)
            axisContext = axis.selectAll()
                .data(intervals)
                .enter()
            axisContext.append('text')
                .attr('text-anchor', 'middle')
                .attr('x', (d) -> d.x)
                .attr('y', '18')
                .text((d) -> d.label)
            axisContext.append('svg:line')
                .attr('x1', (d) -> d.x)
                .attr('x2', (d) -> d.x)
                .attr('y1', '0')
                .attr('y2', '5')
                .attr('stroke', 'black')


        _drawGraph_area: (dataSets, display, height) ->
            width = display.width()
            xmin = dataSets[0][0].x
            xmax = dataSets[0][dataSets[0].length - 1].x

            # d3.layout.stack() adds the "y0" property to dataSets, and stacks 
            # them
            stacks = d3.layout.stack().offset('wiggle')(dataSets)
            ymax = Math.max.apply(Math, stacks.map(
                (a) ->
                    a.reduce(
                        (last, d) ->
                            Math.max(d.y + d.y0, last)
                        0
                    )
            ))

            getAreaMethod = () ->
                useYmax = ymax
                area = d3.svg.area()
                    .x((d) -> (d.x - xmin) * width / (xmax - xmin))
                    .y0((d) -> height - d.y0 * height / useYmax)
                    .y1((d) -> height - (d.y + d.y0) * height / useYmax)
                return area


            # First render
            vis = d3.select(display[0]).append('svg')
            vis.attr('width', width).attr('height', height)
            color = Graph.colors
            self = @
            vis.selectAll("path")
                .data(stacks).enter()
                    .append("path")
                    .style("fill", (d) -> color(d.title))
                    .attr("d", getAreaMethod())
                    .on("mousemove", (d) =>
                        val = @_eventInterp(d)
                        valStr = @_formatValue(val)
                        ui.Tooltip.show(d3.event, d.title + ': ' + valStr)
                    )
                    .on("mouseout", () -> ui.Tooltip.hide())


        _drawGraph_areaZoom: (data, display, height) ->
            ### Draw an area_zoom graph of data in display with height.
            
            data -- DataGroup representing the base values
            ###
            layers = [ [ data, null ] ]
            @__areaZoomContainer = $([])
            @_drawGraph_areaZoom_layer(layers, display, height)
            
            
        _drawGraph_areaZoom_layer: (layers, display, height) ->
            ### Draw the next layer of an area_zoom.  Essentially, for now, 
            wipe display and re-draw the top layer
            ###
            @__areaZoomContainer.remove()
            @__areaZoomContainer = $('<div></div>').appendTo(display)
            
            width = display.width()
            [layerData, detailStackOrder] = layers[layers.length - 1]
            
            # Get combined before bothering with details view, since we need
            # xmin and xmax
            combined = layerData.getGraphPoints()
            console.log("combined")
            console.log(combined)
            
            { xmin, xmax, ymin, ymax } = combined.getBounds()

            # Pixels height for the overall trend graph
            trendHeight = height
            
            if not $.compareObjs({}, layerData.subgroups)
                # We have a 100% expand render to draw; reduce overall trend
                # to 30% height
                trendHeight *= 0.3
                
                # Come up with a list of dataSets
                subgroupSets = []
                for key, subgroup of layerData.subgroups
                    subgroupSets.push(subgroup.getGraphPoints())

                # 100% expand render - remap points to [0..1] based on portion 
                # of _the absolute value_ of combind subgroups
                absCombined = []
                absCombinedMax = 0.0
                for i in [0...subgroupSets[0].length]
                    # Calculate the total "effect" here...
                    absVal = 0
                    for ds in subgroupSets
                        absVal += Math.abs(ds[i].y)
                    absCombined[i] = absVal
                    absCombinedMax = Math.max(absCombinedMax, absVal)
                    
                for i in [0...subgroupSets[0].length]
                    # And now calculate the normalized "ynorm" component for
                    # each subgroup
                    for ds in subgroupSets
                        # If this layer is imperceptible, set ynorm to 0
                        av = Math.abs(ds[i].y)
                        if ds[i].y == 0 or
                                absCombined[i] < absCombinedMax / (2*height)
                            ds[i].ynorm = 0
                        else
                            ds[i].ynorm = Math.abs(ds[i].y) / absCombined[i]
    
                # d3.layout.stack() adds the "y0" property to dataSets, and 
                # stacks them
                stacksGen = d3.layout.stack().offset('zero')
                    .y((d) -> d.ynorm)
                    .out (d, y0, y) ->
                        d.y0 = y0
                
                # We offer click-to-level functionality, since it can be hard
                # to tell the trend of any individual element if it doesn't 
                # have an edge that's a horizontal line
                if detailStackOrder?
                    stackOrder = detailStackOrder
                else
                    stackOrder = [0...subgroupSets.length]
                    
                restackData = () =>
                    # Run the d3.layout.stack on a sorted version of our
                    # subgroupSets; it's nice to keep the order that
                    # we pass them to the visualization the same so 
                    # that the same colors represent the same objects
                    toStack = []
                    for i in stackOrder
                        toStack.push(subgroupSets[i])
                    return stacksGen(toStack)
                    
                # Perform first stack
                restackData()
    
                # Draw the proportional bit
                vis = d3.select(@__areaZoomContainer[0]).append('svg')
                visHeight = height - trendHeight
                vis.attr('width', width).attr('height', visHeight)
                
                self = @
                color = Graph.colors
                area = d3.svg.area()
                area
                    .x((d) -> (d.x - xmin) * width / (xmax - xmin))
                    .y0((d) -> visHeight - d.y0 * visHeight)
                    .y1((d) -> visHeight - (d.ynorm + d.y0) * visHeight)
                vis.selectAll("path")
                    .data(subgroupSets).enter()
                        .append("path")
                        .style("fill", (d) -> color(d.title))
                        .attr("d", area)
                        .on("mousemove", (d) =>
                            val = @_eventInterp(d)
                            valStr = @_formatValue(val)
                            ui.Tooltip.show(d3.event, d.title + ': ' + valStr)
                        )
                        .on("mouseout", () => ui.Tooltip.hide())
                        .on("click", (d, di) =>
                            console.log(arguments)
                            console.log(stackOrder)
                            
                            if di == stackOrder[0]
                                # Already at the bottom, zoom in
                                # Write out our current stackOrder to our
                                # layer so that when it's restored, it will be
                                # sorted like it was before
                                layers[layers.length - 1][1] = stackOrder
                                
                                # Push a new layer and re-render
                                layers.push([ d.group, null ])
                                @_drawGraph_areaZoom_layer(layers, display,
                                        height)
                                return
    
                            # Remove current stackOrder == di and put it at 0
                            # Swap current 0 with stackOrder == di
                            diPos = -1
                            for q, j in stackOrder
                                if q == di
                                    diPos = j
                                    break
    
                            stackOrder = stackOrder[...diPos].concat(
                                stackOrder[diPos + 1..])
                            stackOrder.unshift(di)
                            
                            restackData()
                            vis.selectAll("path")
                                .data(subgroupSets)
                                .transition()
                                    .duration(1000)
                                    .attr("d", area)
                        )

            # Draw the overall trend graph
            # Split combined into combinedp and combinedn - positive and 
            # negative values, respectively.
            combinedp = []
            combinedn = []
            realMax = Math.max(ymax, Math.abs(ymin))
            for val in combined
                fake = $.extend({}, val)
                fake.y = 0
                if val.y >= 0
                    combinedp.push(val)
                    combinedn.push(fake)
                else
                    combinedn.push(val)
                    combinedp.push(fake)
            visn = d3.select(@__areaZoomContainer[0]).append('svg')
            visn.attr('width', width).attr('height', trendHeight - 1)
            $(visn[0]).css('border-top', 'solid 1px #444')
            color = Graph.colors
            visn.selectAll("path")
                .data([ combinedp, combinedn ]).enter()
                    .append("path")
                    .style("fill", (d) => 
                            c = color(combined.title)
                            if d == combinedn
                                # Slightly lighter
                                r = parseInt(c[1..2], 16)
                                g = parseInt(c[3..4], 16)
                                b = parseInt(c[5..6], 16)
                                r += (255 - r) * 0.3
                                g += (255 - g) * 0.3
                                b += (255 - b) * 0.3
                                c = @_getColorHex(r, g, b)
                            return c
                        )
                    .attr(
                        "d"
                        d3.svg.area()
                            .x((d) -> (d.x - xmin) * width / (xmax - xmin))
                            .y0((d) -> trendHeight * (1.0 - Math.abs(d.y) / 
                                    realMax))
                            .y1((d) -> trendHeight)
                    )
                    .on("mousemove", (d) =>
                        text = combined.title + ': '
                        text += @_formatValue(@_eventInterp(d))
                        for key, ds of layerData.subgroups
                            r = @_eventInterp(ds.getGraphPoints())
                            if Math.abs(r) < (ymax - ymin) / height / 2 and
                                    Math.abs(r) < 0.001
                                # Insignificant value
                                continue
                            valStr = @_formatValue(r)
                            text += '<br/>' + ds.title + ': ' + valStr
                        ui.Tooltip.show(d3.event, text)
                    )
                    .on("mouseout", () => ui.Tooltip.hide())
                    .on("click", () =>
                        if layers.length > 1
                            layers.pop()
                            @_drawGraph_areaZoom_layer(layers, display, height)
                    )


        _eventInterp: (dataSet) ->
            ### Use d3.event to interpolate our position in the dataSet, and
            return the interpolated value at this point.
            ###
            x = d3.event.pageX
            svgStart = @_display.offset().left
            svgWidth = @_display.width()
            # For interp, last point happens at far-right, first point
            # happens at svgStart
            interp = (dataSet.length - 1) * (x - svgStart) / svgWidth
            idx = Math.floor(interp)
            idx2 = idx + 1
            if idx2 < dataSet.length
                u = interp - idx
                val = dataSet[idx].y * (1 - u) + dataSet[idx2].y * u
            else
                val = dataSet[idx].y
                
            return val
            
            
        _formatValue: (val) ->
            ### Take a value and format it so it's easier to read
            ###
            
            # Non-integers, change to precision if they're less than
            # a certain amount.  Otherwise, make it by fixed.
            isNeg = (val < 0)
            nval = Math.abs(val)
            if nval == 0
                valStr = '0'
            else if nval > 1000000
                valStr = (nval / 1000000.0).toPrecision(3) + 'M'
            else if nval > 1000
                valStr = (nval / 1000.0).toPrecision(3) + 'K'
            else if nval < 0.000001
                valStr = (nval * 1000000).toPrecision(3) + 'e-6'
            else if nval < 0.001
                valStr = (nval * 1000).toPrecision(3) + 'e-3'
            else
                valStr = nval.toPrecision(3)
            if isNeg
                valStr = '-' + valStr
            return valStr
            
            
        _getColorHex: (r, g, b) ->
            ### Given three numbers from 0-255, return "#abcdef" style string
            ###
            rs = Math.floor(r).toString(16)
            gs = Math.floor(g).toString(16)
            bs = Math.floor(b).toString(16)
            if rs.length < 2
                rs = "0" + rs
            if gs.length < 2
                gs = "0" + gs
            if bs.length < 2
                bs = "0" + bs
            return '#' + rs + gs + bs
            
            
        _hashString: (str) ->
            # Start with a large prime number
            hash = 19175002942688032928599
            for i in [0...str.length]
                char = str.charCodeAt(i)
                # More entropy for small strings
                for q in [0...5]
                    hash = ((hash << 5) - hash) + char
                    hash = hash & hash # Make 32 bit integer
            return hash


        _iterateTargets: (outputs, stats, statData, groups, groupIndex,
                groupValues) ->
            # Come up with all of the statistics we need to load for the 
            # given path parameters
            if groupIndex == groups.length
                for stat in stats
                    t = stat.getTarget(statData)
                    if t of @_statsController.allStats
                        outputs[t] = true
                return

            name = groups[groupIndex][0]
            values = groupValues[name]
            for value in values
                statData[name] = value
                this._iterateTargets(outputs, stats, statData, groups,
                        groupIndex + 1, groupValues)


        _onLoaded: (dataRaw, timeFrom, timeTo, stats) ->
            # timeTo is passed since it might be defined according to the 
            # request (timeFrom as well).  stats passed to avoid re-parsing.
            self = this
            self._display.empty()
            self._loadingOverlay.empty()

            # For drawing the graph, we explicitly don't use self._overlay, 
            # since that gets overwritten if we need to auto-update as fast as 
            # we can.
            loadedText = $('<div class="graph-render-overlay">
                    Loaded, drawing graph</div>')
            loadedText.appendTo(self._display)

            # Set up next autorefresh
            if self._autoRefreshNext != null
                timeToGo = self._autoRefreshNext - (new Date().getTime() / 1000)
                if timeToGo < 0
                    self.update()
                else
                    self._autoRefreshTimeout = setTimeout(
                        () -> self.update()
                        timeToGo * 1000
                    )

            # Step 1 - Parse the data returned to us into datasets
            dataSetsIn = dataRaw.split(/\n/g)
            dataSetsRaw = []
            for dataSetIn in dataSetsIn
                newSet = dataSetIn.split(/[,\|]/g)
                if newSet.length < 4
                    # Empty / bad line
                    continue
                dataSetsRaw.push(newSet)

            # Step 2 - Group those datasets into uniform collections of points
            # aggregated into each group(s) bucket
            # In other words, the data should look like this afterwards:
            # pointTimes = [ timeStampFor0, timeStampFor1, ... ]
            # data = { values: {...}, 
            #       outerGroupValue: { values: { stat: valueList }, 
            #               innerGroupValue: {...} } }
            # where each "values" is an array of aggregate stats at that point
            # with timestamps matching pointTimes
            pointTimes = []
            lastPoint = timeTo
            pointDiff = ((timeTo - timeFrom) / 
                    self.config.graphPoints)
            for i in [0...self.config.graphPoints]
                pointTimes.unshift(lastPoint)
                lastPoint -= pointDiff

            # JS Sandbox
            # Thanks to http://stackoverflow.com/questions/543533/restricting-eval-to-a-narrow-scope
            getMaskedEval = (scr) ->
                ### Returns a function which, given a context ctx, evaluates
                the expression scr and returns the result.

                NOTE - For speed, previous ctx variables are NOT erased, 
                meaning that if a value is NOT specified, it will use the
                value from the last iteration.
                ###
                mask = {}
                for p of this
                    mask[p] = undefined

                fn = new Function("with(this) { return " + scr + "}")

                return (ctx) ->
                    for p of ctx
                        mask[p] = ctx[p]
                    return fn.call(mask)
                    
            # Compile expr
            expr = self.config.expr
            for s, q in stats
                newName = 'v' + q
                expr = expr.replace(s.name, newName)
            myFn = getMaskedEval(expr)
            calculateOptions =
                fn: myFn
                stats: stats
                pointTimes: pointTimes

            data = new DataGroup(self.config.title, calculateOptions)
            for dataSet in dataSetsRaw
                # For each of the returned data sets, nest it in our "totals"
                # data set according to the groups we've been asked to divide
                # across
                dataSetData = self._aggregateSourceData(dataSet, pointTimes,
                        timeFrom)
                dataSetName = dataSetData.stat.name
                myGroups = self.config.groups.slice()
                dataOutput = data
                while true
                    # Merge into current DataGroup
                    if not (dataSetName of dataOutput.values)
                        # There is no existing data at this level; do a copy
                        dataOutput.values[dataSetName] = (
                                dataSetData.values.slice())
                    else
                        # There is existing data at this level; do a merge
                        valuesOut = dataOutput.values[dataSetName]
                        for valueOut, j in dataSetData.values
                            valuesOut[j] += valueOut

                    # Look for the next group that needs the data
                    next = myGroups.shift()
                    if next == undefined
                        # No more groups, all done
                        break
                    nextValue = dataSetData.groups[next[0]]
                    if nextValue == undefined
                        # This stat doesn't have our next group, so stop here
                        break
                    if not (nextValue of dataOutput.subgroups)
                        nextTitle = "#{ next[0] }: #{ nextValue }"
                        dataOutput.subgroups[nextValue] = new DataGroup(
                                nextTitle, calculateOptions)
                    dataOutput = dataOutput.subgroups[nextValue]
            console.log("data")
            console.log(data)

            # ---- Draw the graph ----
            tickHeight = 20
            
            # Render title
            _title = $('<div class="graph-title"></div>').appendTo(
                @_display).text(@config.title)
            _title.bind 'click', () =>
                cfg = $.extend({}, @config)
                # Grab our time basis
                dash = ui.fromDom(@closest('.dashboard'))
                cfg.timeBasis = dash.getTimeBasis()
                cfg.timeAmt = dash.getTimeAmt()
                g = new Graph(cfg)
                page = $('<div class="graph-fullscreen"></div>')
                page.append(g).appendTo('body')
                page.bind 'click', (e) =>
                    if e.target == page[0]
                        page.remove()

            @_drawAxis
                tickHeight: tickHeight
                pointTimes: pointTimes
                display: @_display

            display = self._display
            width = display.width()
            height = display.height() - tickHeight - _title.height()

            drawGraphArgs = [
                data
                @_display
                height
            ]
            if @config.type == 'area'
                @_drawGraph_area.apply(@, drawGraphArgs)
            else if @config.type == 'area-zoom'
                @_drawGraph_areaZoom.apply(@, drawGraphArgs)
            else
                throw "Unknown graph type: " + @config.type

            # Remove loaded message
            loadedText.remove()
            
    # d3.scale.category20 does something cool - it returns a method that gives
    # you a color from a rotating list of 20.  What's cool is that it keeps
    # a map of values it has seen before - that is, if we keep a global
    # category20 instance on Graph, then any graphed value will always have
    # the exact same color in all of our graphs.  Yay!
    Graph.colors = d3.scale.category20()
    return Graph


define(reqs, module)

