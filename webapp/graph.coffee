define [ 'cs!lib/ui.base', 'cs!stat', 'cs!controls' ], (UiBase, Stat, Controls) ->
    class Graph extends UiBase
        constructor: (config) ->
            super('<div class="graph"></div>')
            self = this
            self._statsController = UiBase.fromDom('.stats-app')._statsController

            self._display = $('<div class="display"></div>').appendTo(self)
            self._controls = new Controls(self).appendTo(self)
            self._overlay = $('<div class="overlay"></div>').appendTo(self)

            self._config =
                stat: null
                groups: []
                # Seconds to sum data over for each point
                smoothOver: 0
                # If non-zero, expected value (with smoothOver) at each point
                expectedPerGroup: 0
                # Epoch time (seconds)
                timeFrom: 0
                timeTo: 'now'
                # Seconds between auto refresh
                autoRefresh: 0
                # Points to display on the graph
                graphPoints: 300
            self._autoRefreshTimeout = null
            self._authRefreshNext = null
            self.update(config)


        update: (configChanges) ->
            self = this
            if configChanges
                $.extend(self._config, configChanges)
            
            # Clear out old autorefresh
            if self._autoRefreshTimeout != null
                clearTimeout(self._autoRefreshTimeout)
                self._autoRefreshTimeout = null

            if self._config.stat == null
                self._overlay.empty().append(
                    '<div class="overtop">No data selected</div>'
                )
                return

            self._overlay.empty().append(
                '<div class="overtop">Loading data, please wait</div>'
            )

            # Set new autorefresh
            if self._config.autoRefresh > 0
                self._autoRefreshNext = (new Date().getTime() / 1000)
                self._autoRefreshNext += self._config.autoRefresh
            else
                self._autoRefreshNext = null

            stat = self._config.stat
            if not (stat instanceof Stat)
                stat = self._statsController.stats[stat]

            targets = []
            groups = $.extend([], self._config.groups)
            groupFiltersBase = self._statsController.groups

            groupFilters = {}
            for group in groups
                baseValues = groupFiltersBase[group[0]]
                if group[1] != null
                    groupValues = []
                    groupFilters[group[0]] = groupValues
                    # group[1] is a regex that tells us to include a certain
                    # value
                    for j of baseValues
                        if group[1].test(j)
                            groupValues.push(j)
                else
                    groupFilters[group[0]] = baseValues

            # We don't support * syntax outbound; fill in all possible values
            # that aren't already specified
            for group in stat.groups
                if not (group of groupFilters)
                    groups.push([ group ])
                    groupFilters[group] = groupFiltersBase[group]

            self._iterateTargets(targets, stat, {}, groups, 0, groupFilters)

            timeTo = self._config.timeTo
            if timeTo == 'now'
                timeTo = (new Date().getTime() / 1000)

            $.ajax('getData', {
                type: 'POST'
                data: {
                    targetListJson: JSON.stringify(targets)
                    timeFrom: Math.floor(self._config.timeFrom - 
                            self._config.smoothOver)
                    timeTo: Math.floor(timeTo)
                }
                success: (data) -> self._onLoaded(data, timeTo)
                error: () -> self._overlay.text('Failed to load')
            })


        _aggregateSourceData: (rawData, pointTimes) ->
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

            firstTime = self._config.timeFrom
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
            smoothSecs = self._config.smoothOver
            # Keep track of originally requested smoothing for summations with
            # expected values
            origSmooth = smoothSecs
            if smoothSecs < srcInterval
                # If no smoothing was specified, use the data density
                smoothSecs = srcInterval
            if smoothSecs < pointTimes[1] - pointTimes[0]
                # If smoothing was too small for between points, use point density
                smoothSecs = pointTimes[1] - pointTimes[0]
            console.log("Final smooth: " + smoothSecs)

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
                # expectedPerGroup or specific smoothing intervals)
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
                            if rawData[movingIndex] != 'None'
                                movingTotal -= parseFloat(rawData[movingIndex])
                            movingTime = movingTimeBase + srcInterval
                            movingTimeBase = movingTime
                            movingIndex += 1
                    else if stat.type == 'total'
                        if timeLeft >= partLeft
                            # Take off the whole rest of the point
                            if rawData[movingIndex] != 'None'
                                movingTotal -= (
                                    parseFloat(rawData[movingIndex]) *
                                    partLeft / srcInterval)
                            movingTime = movingTimeBase + srcInterval
                            movingTimeBase = movingTime
                            movingIndex += 1
                        else
                            # Take off part of the point and we're done
                            if rawData[movingIndex] != 'None'
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
                            if rawData[srcIndex] != 'None'
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
                            if rawData[srcIndex] != 'None'
                                movingTotal += (
                                        parseFloat(rawData[srcIndex]) *
                                        partLeft / srcInterval)
                            srcTime = srcTimeBase + srcInterval
                            srcTimeBase = srcTime
                            srcIndex += 1
                        else
                            # Partial point and done
                            if rawData[srcIndex] != 'None'
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


        _iterateTargets: (output, stat, statData, groups, groupIndex,
                groupValues) ->
            if groupIndex == groups.length
                t = stat.getTarget(statData)
                if t of @_statsController.allStats
                    output.push(t)
                return

            name = groups[groupIndex][0]
            values = groupValues[name]
            for value in values
                statData[name] = value
                this._iterateTargets(output, stat, statData, groups,
                        groupIndex + 1, groupValues)


        _onLoaded: (dataRaw, timeTo) ->
            # timeTo is passed since it might be defined according to the request
            self = this
            self._display.empty()
            self._overlay.empty()

            # For drawing the graph, we explicitly don't use self._overlay, since 
            # that gets overwritten if we need to auto-update as fast as we can.
            loadedText = $('<div class="overtop">Loaded, drawing graph</div>')
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
            pointDiff = ((timeTo - self._config.timeFrom) / 
                    self._config.graphPoints)
            for i in [0...self._config.graphPoints]
                pointTimes.unshift(lastPoint)
                lastPoint -= pointDiff

            data = { values: {} }
            for dataSet in dataSetsRaw
                dataSetData = self._aggregateSourceData(dataSet, pointTimes)
                dataSetName = dataSetData.stat.name
                myGroups = self._config.groups.slice()
                dataOutput = data
                while true
                    # Merge at this level
                    if not (dataSetName of dataOutput.values)
                        dataOutput.values[dataSetName] = (
                                dataSetData.values.slice())
                    else
                        valuesOut = dataOutput.values[dataSetName]
                        for valueOut, j in dataSetData.values
                            valuesOut[j] += valueOut

                    # Look for the next group that needs the data
                    next = myGroups.shift()
                    if next == undefined
                        break
                    nextValue = dataSetData.groups[next[0]]
                    if nextValue == undefined
                        # This stat doesn't have our next group, so stop here
                        break
                    if not (nextValue of dataOutput)
                        dataOutput[nextValue] = { values: {} }
                    dataOutput = dataOutput[nextValue]
            console.log(data)

            # ================== ADAPTER CODE ==================
            dataSets = []
            for groupVal of data
                dataSet = data[groupVal]
                if groupVal == 'values'
                    if self._config.groups.length != 0
                        # We have data to display, don't include "values"
                        continue
                    dataSet = data
                
                values = dataSet.values[self._config.stat.name]
                dataSets.push(values.map(
                    (a, i) ->
                        value = a
                        if self._config.expectedPerGroup != 0
                            value = Math.max(
                                self._config.expectedPerGroup - value
                                0
                            )
                        return { x: pointTimes[i], y: value, title: groupVal }
                ))

            #-------------- OLD (relevant) CODE -------------------
            display = self._display
            width = display.width()
            height = display.height() - 32
            vis = d3.select(display[0]).append('svg')
            vis.attr('width', width).attr('height', height)

            xmin = dataSets[0][0].x
            xmax = dataSets[0][dataSets[0].length - 1].x
            intervalMax = xmax
            intervalLength = 60

            if (xmax - xmin) / intervalLength > 20
                intervalLength *= 5
            if (xmax - xmin) / intervalLength > 20
                intervalLength *= 4
            # An hour
            if (xmax - xmin) / intervalLength > 20
                intervalLength *= 3
            # 4 hours?
            if (xmax - xmin) / intervalLength > 20
                intervalLength *= 4
            # A day?
            if (xmax - xmin) / intervalLength > 20
                intervalLength *= 6
            # 5 days?
            if (xmax - xmin) / intervalLength > 20
                intervalLength *= 5
            # 30 days?
            if (xmax - xmin) / intervalLength > 20
                intervalLength *= 6

            # Now that we have "optimal" length, align to nearest whole time unit
            intervalShift = 0
            maxDate = new Date()
            maxDate.setTime(intervalMax * 1000)

            nextReset = maxDate.getSeconds()
            if intervalShift + nextReset < intervalLength
                intervalShift += nextReset
                maxDate.setTime((intervalMax - intervalShift) * 1000)
            nextReset = (maxDate.getMinutes() % 5) * 60
            if intervalShift + nextReset < intervalLength
                intervalShift += nextReset
                maxDate.setTime((intervalMax - intervalShift) * 1000)
            nextReset = (maxDate.getMinutes() % 20) * 60
            if intervalShift + nextReset < intervalLength
                intervalShift += nextReset
                maxDate.setTime((intervalMax - intervalShift) * 1000)
            nextReset = (maxDate.getMinutes() % 30) * 60
            if intervalShift + nextReset < intervalLength
                intervalShift += nextReset
                maxDate.setTime((intervalMax - intervalShift) * 1000)
            nextReset = maxDate.getMinutes() * 60
            if intervalShift + nextReset < intervalLength
                intervalShift += nextReset
                maxDate.setTime((intervalMax - intervalShift) * 1000)
            nextReset = (maxDate.getHours() % 2) * 60 * 60
            if intervalShift + nextReset < intervalLength
                intervalShift += nextReset
                maxDate.setTime((intervalMax - intervalShift) * 1000)
            nextReset = (maxDate.getHours() % 6) * 60 * 60
            if intervalShift + nextReset < intervalLength
                intervalShift += nextReset
                maxDate.setTime((intervalMax - intervalShift) * 1000)
            nextReset = (maxDate.getHours()) * 60 * 60
            if intervalShift + nextReset < intervalLength
                intervalShift += nextReset
                maxDate.setTime((intervalMax - intervalShift) * 1000)
            # Effect the interval
            intervalMax -= intervalShift

            intervals = []
            while intervalMax > xmin
                d = new Date()
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
                .attr('width', width).attr('height', 32)
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

            console.log(dataSets)
            # Stack adds the "y0" property to dataSets, and stacks them
            stack = d3.layout.stack().offset('wiggle')(dataSets)
            ymax = Math.max.apply(Math, stack.map(
                (a) ->
                    a.reduce(
                        (last, d) ->
                            Math.max(d.y + d.y0, last)
                        0
                    )
            ))
            window.stack = stack

            onMouseOver = (d) ->
                x = d3.mouse(this)[0]
                svgWidth = $(this).closest('svg').width()
                idx = Math.floor(x * d.length / svgWidth)
                console.log("OVER " + d[0].title + ", " + d[idx].y)
            
            relativeToAll = false

            getAreaMethod = () ->
                useYmax = dataSets.length * self._config.expectedPerGroup
                if not relativeToAll
                    useYmax = ymax
                area = d3.svg.area()
                    .x((d) -> (d.x - xmin) * width / (xmax - xmin))
                    .y0((d) -> height - d.y0 * height / useYmax)
                    .y1((d) -> height - (d.y + d.y0) * height / useYmax)
                return area

            # First render
            color = d3.interpolateRgb("#aad", "#556")
            vis.selectAll("path")
                .data(stack).enter()
                    .append("path")
                    .style("fill", () -> color(Math.random()))
                    .attr("d", getAreaMethod())
                    .attr("title", (d, i) -> d[0].title)
                    .on("mouseover", onMouseOver)

            # Remove loaded message
            loadedText.remove()

            redraw = () ->
                if self._config.expectedPerGroup > 0
                    relativeToAll = not relativeToAll
                vis.selectAll("path")
                    .data(stack)
                    .transition()
                        .duration(1000)
                        .attr("d", getAreaMethod())

            $('body').unbind('click').bind('click', () -> redraw())


