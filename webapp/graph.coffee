reqs = [ 'cs!lib/ui', 'cs!stat', 'cs!controls', 'cs!dataset', 'cs!datagroup',
        'cs!expressionEvaluator', 'cs!alertEvaluator', 'css!graph' ]
module = (ui, Stat, Controls, DataSet, DataGroup, evaler, AlertEvaluator) ->
    # d3.scale.category20 does something cool - it returns a method that gives
    # you a color from a rotating list of 20.  What's cool is that it keeps
    # a map of values it has seen before - that is, if we keep a global
    # category20 instance on Graph, then any graphed value will always have
    # the exact same color in all of our graphs.  Yay!
    graphColors = d3.scale.category20()
    
    class Graph extends ui.Base
        GRAPH_POINT_DENSITY: 3 #px

        constructor: (config, dashboard) ->
            super('<div class="graph"></div>')
            self = this
            self._statsController = ui.Base.fromDom('.stats-app')._statsController

            @_renderedEventsToClean = []
            self._display = $('<div class="graph-display"></div>').appendTo(
                    self)

            @dashboard = dashboard
            self.config =
                title: '(unnamed)'
                type: 'linear-zoom'
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
            if config
                $.extend(self.config, config)
            self._autoRefreshTimeout = null
            self._authRefreshNext = null
            self._blockAutoRefresh = false

            expanded = not config?
            self._controls = new Controls(self, expanded).appendTo(self)
            self._overlay = $('<div class="graph-overlay"></div>').appendTo(@)
            self._loadingOverlay = $('<div class="graph-loading-overlay">
                    </div>').appendTo(@_overlay)
            self.currentAlerts = []

            if config and @config.alert? and @config.alert != ''
                # We want to trigger alerts immediately, regardless of the state
                # of expand or collapse
                @_requestData(
                        (dataGroup) =>
                            @_updateAlerts(dataGroup)
                        true)


        getTitle: () ->
            """Called when collapsed; when expanded, update() is called."""
            return @config.title


        parseInterval: (interval, defaultInterval = 60*60) ->
            if interval == ''
                return 0

            if /d(y|ay)?s?$/.test(interval)
                #Days
                return parseFloat(interval) * 24 * 60 * 60
            else if /m(in|inute)?s?$/.test(interval)
                #Minutes
                return parseFloat(interval) * 60
            else if /[^a-zA-Z]h(ou)?r?s?$/.test(interval)
                # Hours
                return parseFloat(interval) * 60 * 60
            else if /w(ee)?k?s?$/.test(interval)
                # Weeks
                return parseFloat(interval) * 7 * 24 * 60 * 60
            else if /mon(th)?s?$/.test(interval)
                # Months; 30 days
                return parseFloat(interval) * 30 * 24 * 60 * 60
            else if /y(ea)?r?s?$/.test(interval)
                # Years; 365 days
                return parseFloat(interval) * 365 * 24 * 60 * 60
            else if /\d+$/.test(interval)
                # default
                return parseFloat(interval) * defaultInterval
            else
                throw "Invalid interval: " + interval


        parseAlert: (expr, errorOnUndefined = false) ->
            result = null
            try
                if expr? and expr != ''
                    result = new AlertEvaluator(expr)
            catch e
                # Praser error
                if errorOnUndefined
                    new ui.Dialog(
                        body: "Cannot compile: #{ e }"
                    )
                    throw "Invalid expression"
            return result


        parseStats: (expr, errorOnUndefined = false) ->
            ### Parse an expression for stats, return array of stats used
            ###
            statsFound = []
            try
                compiled = evaler.compile(expr)
            catch e
                # Parser error...
                if errorOnUndefined
                    new ui.Dialog(
                        body: "Cannot compile: #{ e }"
                    )
                    throw "Invalid expression"
                    
                # Otherwise probably just checking as they type...
                return []
                
            recurse = (e) =>
                for k, v of e
                    if k == "op" and v == "s"
                        stat = @_statsController.stats[e.statName]
                        if not stat
                            if errorOnUndefined
                                new ui.Dialog(
                                    body: "Cannot find stat '#{ e.statName }'"
                                )
                                throw "Invalid expression: #{ expr }"
                            
                            # Probably parsing as they type, no need to raise
                            continue
                            
                        statsFound.push(stat)
                    else if v != null and typeof v == 'object'
                        recurse(v)
                        
            recurse(compiled.tree)
            return statsFound


        remove: () ->
            ### Remove this graph and clean up all of its dependency cycles.
            ###
            super
            @_renderedEventsCleanup()
            @_controls.remove()
            @_controls = null


        update: (configChanges) ->
            # Are we no longer in DOM?  break the cycle.
            if @parents('body').length == 0
                @remove()
                return

            self = this
            if configChanges
                # We might have changed, let the dashboard decide
                $.extend(self.config, configChanges)
                self.trigger("needs-save")
            
            # Clear out old autorefresh
            if self._autoRefreshTimeout != null
                clearTimeout(self._autoRefreshTimeout)
                self._autoRefreshTimeout = null

            # Re-allow autorefresh if it's blocked, since we're updating.
            self._blockAutoRefresh = false

            if self.config.expr == null or self.config.expr == ''
                self._createTitle()
                self._display.children().append(' (No data selected)')
                return

            # Set up title and loading stuff
            self._createTitle(true)
            self._display.children(':first').append(
                    ' (<span class="load-percent">0</span>% data loaded)')

            # Set up next autorefresh
            autoRefresh = self._getAutoRefresh()
            if autoRefresh > 0
                self._autoRefreshNext = (new Date().getTime() / 1000)
                self._autoRefreshNext += autoRefresh
            else
                self._autoRefreshNext = null

            self._requestData (dataGroup) => self._drawGraph(dataGroup)


        _requestData: (callback, forAlert = false) ->
            self = @
            stats = self.parseStats(self.config.expr, true)

            # Get all groups from all stats
            allGroups = {}
            for stat in stats
                for group in stat.groups
                    allGroups[group] = true

            # Copy the groups array
            groups = self.config.groups[..]
            availableFiltersBase = self._statsController.groups
            
            # Ensure we respect the global filters; fill out 
            globalFilters = @dashboard.getAllowedGroupValues()
            self._missingFilter = false
            for group of globalFilters
                if group not of allGroups
                    self._missingFilter = true
                    break

            groupFiltersBase = {}
            for group of allGroups
                if group of globalFilters
                    groupFiltersBase[group] = globalFilters[group]
                else
                    # Everything's fair game
                    groupFiltersBase[group] = availableFiltersBase[group]

            groupFilters = {}
            for group in groups
                baseValues = groupFiltersBase[group[0]]
                if group[1] != ''
                    regex = new RegExp('^' + group[1] + '$')
                    groupValues = []
                    groupFilters[group[0]] = groupValues
                    for j in baseValues
                        if regex.test(j)
                            groupValues.push(j)
                else
                    groupFilters[group[0]] = baseValues

            targets = []
            # Build groupFilters into an array of arrays for quick checking of
            # each stat, then iterate over all of our stats for each requested
            # stat and request those that we are actually using.
            groupTargetFilters = []
            for group in stat.groups
                if group not of groupFilters
                    g = {}
                    groupTargetFilters.push(g)
                    for value in groupFiltersBase[group]
                        g[value] = true
                    continue

                values = groupFilters[group]
                g = {}
                groupTargetFilters.push(g)
                for value in values
                    g[value] = true
            #console.log(groupTargetFilters)
            for stat in stats
                for possibleTarget in @_statsController.statToTarget[stat.name]
                    isMatch = true
                    for values, i in groupTargetFilters
                        if (values != null and
                                possibleTarget[i + 1] not of values)
                            isMatch = false
                            break
                    if isMatch
                        targets.push(possibleTarget[0])

            if targets.length == 0
                self._display.empty()
                self._createTitle()
                self._display.children().append(' (Failed to find any source data)')
                return

            timeTo = self.config.timeBasis
            if timeTo == ''
                timeTo = @dashboard.getTimeBasis()
            if timeTo == 'now'
                timeTo = new Date().getTime() / 1000

            timeAmt = self.config.timeAmt
            if timeAmt == ''
                timeAmt = @dashboard.getTimeAmt()
            timeFrom = timeTo - self.parseInterval(timeAmt)
            
            smoothAmt = self.config.smoothOver
            if smoothAmt == ''
                smoothAmt = @dashboard.getSmoothAmt()

            if forAlert
                # For alerts we just need the latest point, plus a small buffer
                # to ensure there are no weird rounding situations.
                timeFrom = timeTo - self.parseInterval(smoothAmt) * 0.3
            
            # Update _sanitize
            @_sanitize = false
            if @dashboard.getSanitize()
                @_sanitize = true

            # Use UTC dates?
            @_utcDates = false
            if @dashboard.getUtcDates()
                @_utcDates = true
                
            # Note that we take off the smoothAmt from timeFrom so that we
            # have the extra data we need to calculate values at the point
            # corresponding to timeFrom
            requestBase =
                timeFrom: Math.floor(timeFrom - self.parseInterval(smoothAmt))
                timeTo: Math.floor(timeTo)
                
            requests = []
            i = 0
            batch = 200
            while i < targets.length
                u = i + batch
                if u > targets.length
                    u = targets.length
                request = $.extend true, {}, requestBase
                request.targetListJson = JSON.stringify(targets[i...u])
                requests.push(request)
                i += batch
                
            loadedData = null
            countRequests = requests.length

            error = () =>
                self._createTitle()
                self._display.children().append(' (Failed to load)')
            gotNext = (data) =>
                if not loadedData?
                    loadedData = data
                else
                    loadedData += '\n' + data
                makeNext()
            makeNext = () =>
                $('.load-percent', self._display).text(
                        (100 * (1 - requests.length / countRequests))
                            .toFixed(0))
                if requests.length == 0
                    self._onLoaded(callback, loadedData, timeFrom, timeTo,
                            stats: stats, smoothAmt: smoothAmt)
                else
                    r = requests.pop()
                    $.ajax('getData', {
                        type: 'POST'
                        data: r
                        success: gotNext
                        error: error
                    })
            makeNext()


        _aggregateSourceData: (rawData, pointTimes, timeFrom, smoothAmt) ->
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
                    # Convert aliased values
                    for group, val of matchGroups
                        groupAliases = self._statsController.aliases[group]
                        if groupAliases and val of groupAliases
                            matchGroups[group] = groupAliases[val]
                    break

            if matchStat == null
                throw "Could not match stat: " + rawData[0]

            result = { stat: matchStat, groups: matchGroups }
            values = []
            result.values = values
            
            aggregateType = 'count'
            if stat.type == 'total' or stat.type == 'total-max'
                aggregateType = 'total'
            else if stat.type == 'count-fuzzy'
                aggregateType = 'count-fuzzy'
            
            # First thing's first - if we're a total, we need to replace all
            # 'None' values an interpolation of the next and last values.
            # If we're a count, just replace all 'None' values with 0.
            hasData = false
            if aggregateType == 'total'
                lastValue = null
                lastValueI = 0
                nextValue = null
                nextValueI = -1
                for i in [4...rawData.length]
                    if rawData[i] != 'None'
                        hasData = true
                        lastValue = parseFloat(rawData[i])
                        lastValueI = i
                    else
                        if i > nextValueI
                            for j in [i + 1...rawData.length]
                                if rawData[j] != 'None'
                                    nextValueI = j
                                    nextValue = parseFloat(rawData[j])
                                    break
                            if i > nextValueI
                                # No more data; drag out last value
                                nextValueI = rawData.length
                                nextValue = null

                        if lastValue == null
                            # Haven't seen any values, use nextValue
                            rawData[i] = nextValue
                        else if nextValue == null
                            rawData[i] = lastValue
                        else
                            # Interpolate!
                            u = (i - lastValueI) / (nextValueI - lastValueI)
                            rawData[i] = u * nextValue + (1.0 - u) * lastValue
                        # TODO here
                        # If this were assigned 0, AND right-edge detection
                        # were to be fixed (that is, a lack of reported values
                        # should produce a gap), then we'd be able to tell when
                        # an expected stat wasn't reported.
            else if aggregateType == 'count' or aggregateType == 'count-fuzzy'
                for i in [4...rawData.length]
                    if rawData[i] == 'None'
                        rawData[i] = 0
                    else
                        hasData = true
            else
                throw "Invalid aggregateType: " + aggregateType

            if not hasData
                # This set doesn't have any data, so don't return it.
                return null

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
            smoothSecs = self.parseInterval(smoothAmt)
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

            if aggregateType == 'count-fuzzy'
                # Aggregate via bubbling... each pointTime is affected by the
                # buckets around it according to their distance from the
                # affected point.
                # Note - this method MUST maintain maximum values (e.g. the
                # graph maximum for a single point is the point's value).
                # A good name for this might be "fuzzy counter", since it is
                # essentially a stat with some stochastic occurrance.
                for pt in pointTimes
                    values.push(0)

                lastPoint = pointTimes[pointTimes.length - 1]
                firstPoint = pointTimes[0]

                # I've tried to square or cube the falloff, but linear just
                # works out the best, partly because a smoothSecs equaling the
                # period of a uniformly distributed event then looks completely
                # even.
                falloff = 1
                for index in [srcIndex...rawData.length]
                    v = parseFloat(rawData[index])
                    vt = srcTime

                    for pointTime, i in pointTimes
                        dist = Math.abs(pointTime - vt)
                        if dist < smoothSecs
                            magnitude = Math.pow(
                                    1.0 - Math.abs(dist / smoothSecs), falloff)

                            # Would our mirror around point time be off either
                            # side of the graph?  Granted this is a little
                            # "predictive", but it preserves the curvature
                            # around points given the lack of data
                            edgeDist = vt + smoothSecs - lastPoint
                            if edgeDist > 0 and lastPoint - edgeDist < pointTime
                                # So, we want to integrate the region that
                                # we're missing (edgeDist) into the region
                                # between the end of our data set and
                                # edgeDist before the end of our data set.
                                # Essentially, mirroring in the missing area.
                                pointMag = 1.0 - (lastPoint - pointTime) /
                                        edgeDist
                                if pointMag > 0
                                    pointMag *= edgeDist / smoothSecs
                                    pointMag = Math.pow(pointMag, falloff)
                                    magnitude += pointMag

                            values[i] += v * magnitude

                            # Note, we don't apply edge wrapping to the past
                            # side of the graph, since we already request
                            # smoothSecs of extra historical data.  In other
                            # words, this side is already an accurate graph

                    # Next point happens in the future...
                    srcTime += srcInterval

                # And done
                return result


            movingTotal = 0.0
            movingIndex = srcIndex

            # We've removed up to this point of current point
            movingTime = srcTime
            # The start of current point
            movingTimeBase = movingTime
            
            # In order to get true zeros when we have no stats counted,
            # keep track of the number of stats in our range
            # nz - non-zero
            nzStatsInRange = 0
            # Used for total to ensure that we average all points in the window
            # correctly.
            nzStatParts = 0

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

                    if aggregateType == 'count'
                        if timeLeft < partLeft
                            # Remove none of count's value until the data point
                            # is completely out of the window
                            movingTime = newTail
                        else
                            # Remove the whole value
                            v = parseFloat(rawData[movingIndex])
                            movingTotal -= v
                            movingTime = movingTimeBase + srcInterval
                            movingTimeBase = movingTime
                            movingIndex += 1
                            if v != 0
                                nzStatsInRange -= 1
                                if nzStatsInRange == 0
                                    movingTotal = 0.0
                    else if aggregateType == 'total'
                        v = parseFloat(rawData[movingIndex])
                        if timeLeft >= partLeft
                            # Take off the whole rest of the point
                            movingTotal -= (v *
                                    partLeft / srcInterval)
                            movingTime = movingTimeBase + srcInterval
                            movingTimeBase = movingTime
                            movingIndex += 1
                            if v != 0
                                nzStatParts -= partLeft / srcInterval
                                nzStatsInRange -= 1
                                if nzStatsInRange == 0
                                    movingTotal = 0.0
                                    nzStatParts = 0
                        else
                            # Take off part of the point and we're done
                            movingTotal -= (v *
                                    timeLeft / srcInterval)
                            if v != 0
                                nzStatParts -= timeLeft / srcInterval
                            movingTime = newTail

                while srcIndex < rawData.length and srcTime < pointTime
                    # Moving summation
                    timeLeft = pointTime - srcTime
                    partLeft = srcTimeBase + srcInterval - srcTime

                    if aggregateType == 'count'
                        # We want the first instance to count for everything
                        if srcTime == srcTimeBase
                            # We're at first point, add it
                            v = parseFloat(rawData[srcIndex])
                            movingTotal += v
                            if v != 0
                                nzStatsInRange += 1

                        # Are we going to a new point?
                        if timeLeft >= partLeft
                            srcTime = srcTimeBase + srcInterval
                            srcTimeBase = srcTime
                            srcIndex += 1
                        else
                            srcTime = pointTime
                    else if aggregateType == 'total'
                        # First instance of this point entering our range?
                        v = parseFloat(rawData[srcIndex])
                        if srcTime == srcTimeBase and v != 0
                            nzStatsInRange += 1
                            
                        if timeLeft >= partLeft
                            # Rest of the point!
                            movingTotal += (v *
                                    partLeft / srcInterval)
                            if v != 0
                                nzStatParts += partLeft / srcInterval
                            srcTime = srcTimeBase + srcInterval
                            srcTimeBase = srcTime
                            srcIndex += 1
                        else
                            # Partial point and done
                            movingTotal += (v *
                                    timeLeft / srcInterval)
                            if v != 0
                                nzStatParts += timeLeft / srcInterval
                            srcTime = pointTime

                # Now, add!
                if aggregateType == 'count'
                    # For counts, if we wanted a smaller time range than
                    # the smoothing interval, we'll need to scale it down
                    if origSmooth != 0
                        values.push(movingTotal * origSmooth / smoothSecs)
                    else
                        # We want to use data density
                        values.push(movingTotal)
                else if aggregateType == 'total'
                    # These are set values, so adjust smoothing according to
                    # the srcInterval
                    if nzStatParts > 0
                        values.push(movingTotal / nzStatParts)
                    else
                        values.push(0)
                else
                    throw "Stat type summation not defined: " + stat.type

            # Done!
            return result


        _autoRefresh: () ->
            ###Refresh!
            ###

            # Do we no longer have permission to auto refresh?
            if not (@_getAutoRefresh() > 0)
                return

            if @_blockAutoRefresh
                @_autoRefreshTimeout = setTimeout(
                        () => @_autoRefresh(),
                        1000)
            else
                @update()
            
            
        _calculateSanitize: (valSets) ->
            ### Given a set of sets of non-zero absolute values, 
            calculate the upper bound to display for a sanitized view.
            ###
            
            sanitizedMin = 0.0
            
            for set in valSets
                lessVals = set
                tries = 5 # Bound the # of standard deviation passes
                avg = 0.0
                stddev = 0.0
                while tries > 0 and lessVals.length > 0
                    tries -= 1
                    avg = d3.mean(lessVals)
                    stddev = 0.0
                    for v in lessVals
                        stddev += Math.pow(v - avg, 2)
                    stddev = Math.sqrt(stddev / lessVals.length)
                    
                    if stddev <= avg * 4 + 1e-6
                        break
                        
                    # Another iteration; crop anything outside the first deviation
                    lessVals = lessVals.filter((a) -> a <= avg + stddev * 2)
                sanitizedMin = Math.max(sanitizedMin, avg + stddev * 5)
                    
            return sanitizedMin
                
                
            stddev = 0.0
            for v in allVals
                stddev += Math.pow(v - avg, 2)
            stddev = Math.sqrt(stddev / allVals.length)
            
            # Ok, now that we have our standard deviation, do it again, but
            # this time only include values within 2 standard deviations.
            # This smooths out extreme peaks nicely
            top = avg + stddev * 2
            lessVals = allVals.filter((a) -> a <= top)
            
            # Re-calculate stddev, and use that amount
            stddev2 = 0.0
            newAvg = d3.mean(lessVals)
            for v in lessVals
                stddev2 += Math.pow(v - newAvg, 2)
            stddev2 = Math.sqrt(stddev2 / lessVals.length)
            
            # Since the remaining points are considered "sane", we include a
            # lot more standard deviations
            return newAvg + stddev2 * 5
            
            
        _createTitle: (keepDisplay) ->
            titleHtml = '<div class="graph-title"></div>'
            if not keepDisplay
                @_display.empty()
                @_loadingOverlay.empty()
                title = $(titleHtml).appendTo(@_display)
            else
                @_loadingOverlay.empty()
                title = @_display.children(':first')
                if title.length == 0
                    title = $(titleHtml).appendTo(@_display)
            title.text(@config.title)
            if @_missingFilter
                title.append('<span style="color:#f00;"> missed by filter</span>')
            return title
        
        
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

            getSeconds = Date.prototype.getSeconds
            getMinutes = Date.prototype.getMinutes
            getHours = Date.prototype.getHours
            getDate = Date.prototype.getDate
            getMonth = Date.prototype.getMonth
            if @_utcDates
                getSeconds = Date.prototype.getUTCSeconds
                getMinutes = Date.prototype.getUTCMinutes
                getHours = Date.prototype.getUTCHours
                getDate = Date.prototype.getUTCDate
                getMonth = Date.prototype.getUTCMonth

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
                () -> getSeconds.call(maxDate)
                () -> (getMinutes.call(maxDate) % 5) * 60
                () -> (getMinutes.call(maxDate) % 20) * 60
                () -> (getMinutes.call(maxDate) % 30) * 60
                () -> getMinutes.call(maxDate) * 60
                () -> (getHours.call(maxDate) % 2) * 60*60
                () -> (getHours.call(maxDate) % 6) * 60*60
                () -> getHours.call(maxDate) * 60*60
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
                leftInDay = (getHours.call(d) * 60 * 60 +
                        getMinutes.call(d) * 60)
                if intervalLength > leftInDay
                	intervalMax -= leftInDay
                	d.setTime(intervalMax * 1000)

                if getHours.call(d) == 0 and getMinutes.call(d) == 0
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
                    label = (months[getMonth.call(d)] +
                            getDate.call(d).toString())
                else
                    # Hour : Minute timestamps
                    hrs = getHours.call(d).toString()
                    if d.getMinutes() == 0
                        mins = 'h'
                    else
                        mins = getMinutes.call(d).toString()
                        if mins.length < 2
                            mins = '0' + mins
                        mins = ':' + mins
                    label = hrs + mins

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


        _drawGraph: (data) ->
            # Called when entirely new data is available for the graph (in other
            # words, for all the zoom graphs, this is called only once
            # regardless of zooming around).
            # data is the processed DataGroup aggregated from _onLoaded.

            self = @

            if @_blockAutoRefresh
                # We probably don't actually want to commit the data...
                @_createTitle(true)
                @_display.children(':first').append(
                        ' (New data loaded, waiting)')
                origArgs = arguments
                setTimeout(
                        () => @_onLoaded.apply(@, origArgs)
                        1000)
                return

            # Unbind d3 event listeners to prevent leaks...  Do this in a
            # closure so that we forget entirely about last round's events
            # to clean.
            @_renderedEventsCleanup()

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
                    timeToGo = 0

                self._autoRefreshTimeout = setTimeout(
                    () -> self._autoRefresh()
                    timeToGo * 1000
                )

            # Parse out alerts - note that this must be only during a load,
            # NOT when the graph's perspective is changed.  This should only
            # apply to the top division.
            @_updateAlerts(data)

            # ---- Draw the graph ----
            tickHeight = 20

            # Render title_title =
            _title = self._createTitle()
            _title.bind 'click', () =>
                cfg = $.extend({}, @config)
                # Grab our time basis
                cfg.timeBasis = @dashboard.getTimeBasis()
                cfg.timeAmt = @dashboard.getTimeAmt()
                g = new Graph(cfg, @dashboard)
                page = $('<div class="graph-fullscreen"></div>')
                page.append(g).appendTo('body')
                g.update()
                page.bind 'click', (e) =>
                    if e.target == page[0]
                        page.remove()

            @_drawAxis
                tickHeight: tickHeight
                pointTimes: data.computeOptions.pointTimes
                display: @_display

            display = self._display
            width = display.width()
            height = display.height() - tickHeight - _title.height()

            drawGraphArgs = [
                data
                @_display
                height
            ]
            if @config.type == 'area-period'
                drawGraphArgs.push('area-period')
                @_drawGraph_zoom.apply(@, drawGraphArgs)
            else if @config.type == 'area-zoom'
                drawGraphArgs.push('area')
                @_drawGraph_zoom.apply(@, drawGraphArgs)
            else if @config.type == 'linear-zoom'
                drawGraphArgs.push('linear')
                @_drawGraph_zoom.apply(@, drawGraphArgs)
            else
                throw "Unknown graph type: " + @config.type

            # Remove loaded message
            loadedText.remove()


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
            self = @
            vis.selectAll("path")
                .data(stacks).enter()
                    .append("path")
                    .style("fill", (d) -> graphColors(d.title))
                    .attr("d", getAreaMethod())
                    .on("mousemove", (d) =>
                        val = @_eventInterp(d)
                        valStr = @_formatValue(val)
                        ui.Tooltip.show(d3.event, d.title + ': ' + valStr)
                    )
                    .on("mouseout", () -> ui.Tooltip.hide())

            # Circular reference cleanup
            @_registerRenderedEvents(vis, [ "mousemove", "mouseout" ])


        _drawGraph_zoom: (data, display, height, zoomType) ->
            ### Draw an area_zoom graph of data in display with height.
            
            data -- DataGroup representing the base values
            ###
            layers = [ [ data, null ] ]
            @__zoomContainer = $([])
            options =
                layers: layers
                display :display
                height: height
                zoomType: zoomType
            @_drawGraph_zoom_layer(options)
            
            
        _drawGraph_zoom_layer: (options) ->
            ### Draw the next layer of an area_zoom.  Essentially, for now, 
            wipe display and re-draw the top layer
            ###
            
            # De-compress options
            {layers, display, height, zoomType} = options

            if layers.length > 1
                # Don't interrupt work with an auto refresh!
                @_blockAutoRefresh = true
            else
                @_blockAutoRefresh = false
            
            @__zoomContainer.remove()
            @__zoomContainer = $('<div></div>').appendTo(display)
            
            width = display.width()
            [layerData, detailStackOrder] = layers[layers.length - 1]
            
            # Get combined before bothering with details view, since we need
            # xmin and xmax
            combined = layerData.getGraphPoints()
            if window.debug
                console.log("combined")
                console.log(combined)
            
            { xmin, xmax, ymin, ymax } = combined.getBounds()

            # Pixels height for the overall trend graph
            trendHeight = height
            
            if not $.compareObjs({}, layerData.subgroups)
                # We have a 100% expand render to draw; reduce overall trend
                # to 30% height
                trendHeight = Math.floor(trendHeight * 0.3)
                
                # Come up with a list of dataSets
                subgroupSets = []
                for key, subgroup of layerData.subgroups
                    subgroupSets.push(subgroup.getGraphPoints())
                
                # Figure out what type of subgroup rendering we're doing...
                detailHeight = height - trendHeight
                detailVis = d3.select(@__zoomContainer[0]).append('svg')
                    .attr('width', width)
                    # Take 1 px off height for border
                    .attr('height', detailHeight - 1)
                $(detailVis[0]).css('border-top', 'solid 1px #444')
                if zoomType == 'area'
                    @_drawGraph_zoom_layer_area(options, detailVis, 
                            subgroupSets)
                else if zoomType == 'linear'
                    @_drawGraph_zoom_layer_linear(options, detailVis,
                            subgroupSets)
                else if zoomType == 'area-period'
                    @_drawGraph_zoom_layer_area_period(options, detailVis,
                            subgroupSets)
                else
                    throw "Invalid render zoom type - " + zoomType
                    
            # Figure out the graphable ymax
            realMax = Math.max(ymax, Math.abs(ymin))
                    
            # Do we need to clamp ymax / ymin?
            if @_sanitize
                # Use 2 standard deviations for cap
                allVals = []
                for pt in combined
                    v = Math.abs(pt.y)
                    if v > 0
                        # Don't count points that don't have scale; we're more
                        # interested in the deviation of valued points
                        allVals.push(v)
                topStddev = @_calculateSanitize([ allVals ])
                if topStddev < realMax
                    isCapped = true
                    realMax = topStddev

            # Draw the overall trend graph
            # Split combined into combinedp and combinedn - positive and 
            # negative values, respectively.
            combinedp = []
            combinedn = []
            for val in combined
                fake = $.extend({}, val)
                fake.y = 0
                if val.y >= 0
                    combinedp.push(val)
                    combinedn.push(fake)
                else
                    combinedn.push(val)
                    combinedp.push(fake)
            visn = d3.select(@__zoomContainer[0]).append('svg')
            magLabel = $('<div class="graph-display-label-max"></div>')
                .text(@_formatValue(realMax))
                .insertBefore(visn[0])
            if isCapped
                magLabel.css('color', '#f44')
            visn.attr('width', width).attr('height', trendHeight - 1)
            $(visn[0]).css('border-top', 'solid 1px #444')
            
            # Fix divide by zero (after filling out graph-label-max)
            if realMax == 0
                realMax = 1
                
            # Coffee-script workaround... should look at why this can't be
            # inlined.
            y0Get = (d) ->
                # Sanitize can mean > 1.0 results here
                pt = Math.min(1.0, Math.abs(d.y) / realMax)
                return trendHeight * (1.0 - pt)
            
            visn.selectAll("path")
                .data([ combinedp, combinedn ]).enter()
                    .append("path")
                    .style("fill", (d) =>
                            if d == combinedn
                                c = @_getNegativeColor(combined.title)
                            else
                                c = graphColors(combined.title)
                            return c
                        )
                    .attr(
                        "d"
                        d3.svg.area()
                            .x((d) -> (d.x - xmin) * width / (xmax - xmin))
                            .y0(y0Get)
                            .y1((d) -> trendHeight)
                    )
                    .on("mousemove", (d) =>
                        tipDiv = $('<div class="graph-value-tooltip"></div>')
                        tipDiv.append(combined.title + ': ')
                        tipDiv.append(@_getTipSwatch(combined.title))
                        tipDiv.append(@_formatValue(@_eventInterp(d)))
                        
                        # Compile a list of subgroups that affect this value,
                        # and sort their tooltips and append
                        subtips = []
                        for key, ds of layerData.subgroups
                            r = @_eventInterp(ds.getGraphPoints())
                            if Math.abs(r) < (ymax - ymin) / height / 2 and
                                    Math.abs(r) < 0.001
                                # Insignificant value
                                continue
                            valStr = @_formatValue(r)
                            valLine = $('<div></div>')
                            valLine.append(ds.title + ': ')
                            valLine.append(@_getTipSwatch(ds.title))
                            valLine.append(valStr)
                            subtips.push([ valLine, r ])
                            
                        subtips.sort (a,b) -> Math.abs(b[1]) - Math.abs(a[1])
                        for tip in subtips
                            tipDiv.append(tip[0])
                        ui.Tooltip.show(d3.event, tipDiv)
                    )
                    .on("mouseout", () => ui.Tooltip.hide())
                    .on("click", () =>
                        if layers.length > 1
                            layers.pop()
                            @_drawGraph_zoom_layer(options)
                    )

            # Circular reference cleanup
            @_registerRenderedEvents(visn, [ "mousemove", "mouseout", "click" ])
                    
                    
        _drawGraph_zoom_layer_area: (options, detailVis, subgroupSets) ->
            # 100% expand render - remap points to [0..1] based on portion 
            # of _the absolute value_ of combind subgroups
            
            # De-compress options
            {layers, display, height, zoomType} = options
            width = $(detailVis[0]).width()
            height = $(detailVis[0]).height()
            xmin = subgroupSets[0][0].x
            xmax = subgroupSets[0][subgroupSets[0].length - 1].x
            
            absCombined = []
            absCombinedMax = 0.0
            for i in [0...subgroupSets[0].length]
                # Calculate the total "effect" here...
                absVal = 0
                for ds in subgroupSets
                    absVal += Math.abs(ds[i].y)
                absCombined[i] = absVal
                absCombinedMax = Math.max(absCombinedMax, absVal)
                
            # No label for y-max on area slices... the fact that it's fully
            # colored makes it hard to see, and it's the same max as the
            # bottom division at any rate
            #$('<div class="graph-display-label-max"></div>')
            #    .text(@_formatValue(absCombinedMax))
            #    .insertBefore(detailVis[0])
                
            # Fix the error case where there are almost no values
            if absCombinedMax == 0
                absCombinedMax = 1
                
            for i in [0...subgroupSets[0].length]
                # And now calculate the normalized "ynorm" component for
                # each subgroup
                for ds in subgroupSets
                    # If this layer is imperceptible, set ynorm to 0
                    av = Math.abs(ds[i].y)
                    if ds[i].y == 0 or absCombined[i] < 1e-6
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
            detailStackOrder = layers[layers.length - 1][1]
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
            self = @
            area = d3.svg.area()
            area
                .x((d) -> (d.x - xmin) * width / (xmax - xmin))
                .y0((d) -> height - d.y0 * height)
                .y1((d) -> height - (d.ynorm + d.y0) * height)
            detailVis.selectAll("path")
                .data(subgroupSets).enter()
                    .append("path")
                    .style("fill", (d) -> graphColors(d.title))
                    .attr("d", area)
                    .on("mousemove", (d) =>
                        val = @_eventInterp(d)
                        valStr = @_formatValue(val)
                        tip = $('<div class="graph-value-tooltip"></div>')
                        tip.append(d.title + ': ')
                        tip.append(@_getTipSwatch(d.title))
                        tip.append(valStr)
                        ui.Tooltip.show(d3.event, tip)
                    )
                    .on("mouseout", () => ui.Tooltip.hide())
                    .on("click", (d, di) =>
                        if window.debug
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
                            @_drawGraph_zoom_layer(options)
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
                        detailVis.selectAll("path")
                            .data(subgroupSets)
                            .transition()
                                .duration(1000)
                                .attr("d", area)
                    )

            # Circular reference cleanup
            @_registerRenderedEvents(detailVis, [ "mousemove", "mouseout",
                    "click" ])
                    
                    
        _drawGraph_zoom_layer_area_period: (options, detailVis, subgroupSets) ->
            # Remap points to [0..1] based on portion
            # of _the absolute value_ of combined subgroups, but with respect
            # to each element's personal greatest.

            # That is, for each point in time for each subgroup, map from [0, 1]
            # according to the absolute value's proportion of the maximum
            # absolute value for that subgroup.  Then, for each point in time,
            # display EITHER a 100% stacked or a normal stack of those
            # proportions

            # De-compress options
            {layers, display, height, zoomType} = options
            width = $(detailVis[0]).width()
            height = $(detailVis[0]).height()
            xmin = subgroupSets[0][0].x
            xmax = subgroupSets[0][subgroupSets[0].length - 1].x

            # Find the max per subgroup
            subgroupMax = []
            for ds in subgroupSets
                max = 0
                for i in [0...ds.length]
                    max = Math.max(Math.abs(ds[i].y), max)
                # No data points?  Use 1 to avoid division errors
                if max == 0
                    max = 1
                subgroupMax.push(max)

            # No label for y-max on area slices... the fact that it's fully
            # colored makes it hard to see, and it's the same max as the
            # bottom division at any rate
            #$('<div class="graph-display-label-max"></div>')
            #    .text(@_formatValue(absCombinedMax))
            #    .insertBefore(detailVis[0])

            # Normalize each subgroup's data to [0..1]
            scalar = (v) -> v
            scalar = (v) -> Math.log(v + 1)
            absoluteMax = 0
            for i in [0...subgroupSets[0].length]
                spotMax = 0
                for ds, j in subgroupSets
                    ds[i].ynormAlone = Math.abs(ds[i].y) / subgroupMax[j]
                    spotMax = Math.max(scalar(ds[i].ynormAlone), spotMax)
                absoluteMax = Math.max(spotMax, absoluteMax)

            # Normalize all data points according to the absolute max
            if absoluteMax == 0
                absoluteMax = 1

            # Keep track of the sum of all of a series' points so that we can
            # sort the lines to minimize occlusion.
            groupSums = []
            for ds, i in subgroupSets
                groupSum = 0.0
                for j in [0...ds.length]
                    ds[j].ynorm = (ds[j].ynormAlone *
                            scalar(ds[j].ynormAlone) / absoluteMax)
                    groupSum += ds[j].ynorm
                groupSums.push([ i, groupSum ])

            # d3.layout.stack() adds the "y0" property to dataSets, and
            # stacks them
            stacksGen = d3.layout.stack().offset('zero')
                .y((d) -> d.ynorm)
                .out (d, y0, y) ->
                    d.y0 = y0

            # We offer click-to-level functionality, since it can be hard
            # to tell the trend of any individual element if it doesn't
            # have an edge that's a horizontal line
            detailStackOrder = layers[layers.length - 1][1]
            if detailStackOrder?
                stackOrder = detailStackOrder
            else
                stackOrder = groupSums[..]
                stackOrder.sort (a, b) -> b[1] - a[1]
                stackOrder = (s[0] for s in stackOrder)

            reorderedSubGroups = []
            for i in stackOrder
                reorderedSubGroups.push(subgroupSets[i])
            # Populate positions
            stacksGen(reorderedSubGroups)

            # Draw the proportional bit
            self = @
            area = d3.svg.area()
            area
                .x((d) -> (d.x - xmin) * width / (xmax - xmin))
                .y0((d) -> height - 0*d.y0 * height)
                .y1((d) -> height - (d.ynorm + 0*d.y0) * height)
            detailVis.selectAll("path")
                .data(reorderedSubGroups).enter()
                    .append("path")
                    .style("fill", (d) -> graphColors(d.title))
                    .attr("d", area)
                    .on("mousemove", (d) =>
                        val = @_eventInterp(d)
                        valStr = @_formatValue(val)
                        tip = $('<div class="graph-value-tooltip"></div>')
                        tip.append(d.title + ': ')
                        tip.append(@_getTipSwatch(d.title))
                        tip.append(valStr)
                        ui.Tooltip.show(d3.event, tip)
                    )
                    .on("mouseout", () => ui.Tooltip.hide())
                    .on("click", (d, di) =>
                        if window.debug
                            console.log(arguments)
                            console.log(stackOrder)

                        # Already at the bottom, zoom in
                        # Write out our current stackOrder to our
                        # layer so that when it's restored, it will be
                        # sorted like it was before
                        layers[layers.length - 1][1] = stackOrder

                        # Push a new layer and re-render
                        layers.push([ d.group, null ])
                        @_drawGraph_zoom_layer(options)
                        return
                    )

            # Circular reference cleanup
            @_registerRenderedEvents(detailVis, [ "mousemove", "mouseout",
                    "click" ])


        _drawGraph_zoom_layer_linear: (options, detailVis, subgroupSets) ->
            # Render absolute values as lines of the composite combined value,
            # according to their magnitude
            
            # De-compress options
            {layers, display, height, zoomType} = options
            width = $(detailVis[0]).width()
            height = $(detailVis[0]).height()
            xmin = subgroupSets[0][0].x
            xmax = subgroupSets[0][subgroupSets[0].length - 1].x
            
            # For linear, everything will be plotted on an absolute value
            # scale from [0..greatext y value]
            ymax = 0.0
            for i in [0...subgroupSets[0].length]
                for ds in subgroupSets
                    ymax = Math.max(ymax, Math.abs(ds[i].y))
                    
            # Do we need to clamp ymax?
            if @_sanitize
                # Use 2 standard deviations for cap
                allValSets = []
                for ds in subgroupSets
                    allVals = []
                    for i in [0...subgroupSets[0].length]
                        v = Math.abs(ds[i].y)
                        if v > 0
                            # Don't count points that don't have scale; we're 
                            # more interested in the deviation of valued points
                            allVals.push(v)
                    allValSets.push(allVals)
                            
                topStddev = @_calculateSanitize(allValSets)
                if topStddev < ymax
                    ymax = topStddev
                    isCapped = true
                
            # Draw our magnitude label
            magLabel = $('<div class="graph-display-label-max"></div>')
                .text(@_formatValue(ymax))
                .insertBefore(detailVis[0])
            if isCapped
                magLabel.css('color', '#f44')
                    
            # Fix the error case
            if ymax == 0
                ymax = 1
                
            # And now calculate the normalized "ynorm" component for
            # each subgroup at each point... except split it into ynormp and
            # ynormn, since negative and positive lines should be colored 
            # slightly differently.
            for i in [0...subgroupSets[0].length]
                for ds in subgroupSets
                    ds[i].ynormp = 0.0
                    ds[i].ynormn = 0.0
                    # We have to clamp val here, since sanitize may have 
                    # changed the render range
                    val = Math.min(1, Math.abs(ds[i].y) / ymax)
                    if ds[i].y > 0
                        ds[i].ynormp = val
                    else
                        ds[i].ynormn = val

            # Draw the proportional bit
            normWidth = '2px'
            selWidth = '5px'
            
            # Set up mouse handler here since we use it for both positive 
            # and negative
            self = @
            mousemove = (d) ->
                val = self._eventInterp(d)
                valStr = self._formatValue(val)
                tip = $('<div class="graph-value-tooltip"></div>')
                tip.append(d.title + ': ')
                        .append(self._getTipSwatch(d.title))
                        .append(valStr)
                ui.Tooltip.show(d3.event, tip)
                # Make this line thicker
                $(@).css("stroke-width", selWidth)
            mouseout = (d) ->
                ui.Tooltip.hide()
                $(@).css("stroke-width", normWidth)
            click = (d) =>
                # Push a new layer and re-render
                layers.push([ d.group, null ])
                @_drawGraph_zoom_layer(options)
                
            linep = d3.svg.line()
                .interpolate('monotone')
                .x((d) => (d.x - xmin) * width / (xmax - xmin))
                .y((d) => height - d.ynormp * height)
            linen = d3.svg.line()
                .interpolate('monotone')
                .x((d) => (d.x - xmin) * width / (xmax - xmin))
                .y((d) => height - d.ynormn * height)
                
            visData = detailVis.selectAll("path").data(subgroupSets).enter()
            
            # Positives!
            visData
                .append("path")
                .attr("class", "line")
                .style("stroke", (d) => graphColors(d.title))
                .style("stroke-width", normWidth)
                .style("fill", "none")
                .attr("d", linep)
                .on("mousemove", mousemove)
                .on("mouseout", mouseout)
                .on("click", click)
                
            # Negatives!
            visData
                .append("path")
                .attr("class", "line")
                .style("stroke", (d) => @_getNegativeColor(d.title))
                .style("stroke-width", normWidth)
                .style("fill", "none")
                .attr("d", linen)
                .on("mousemove", mousemove)
                .on("mouseout", mouseout)
                .on("click", click)

            # Circular reference cleanup
            @_registerRenderedEvents(detailVis, [ "mousemove", "mouseout",
                    "click" ])


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
            else if nval > 1000000000
                valStr = (nval / 1000000000.0).toPrecision(3) + 'B'
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


        _getAutoRefresh: () ->
            # Return the current auto refresh interval in seconds
            autoRefresh = @config.autoRefresh
            if autoRefresh == ''
                autoRefresh = @dashboard.getAutoRefresh()
            return autoRefresh
            
            
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
            
            
        _getNegativeColor: (colorKey) ->
            ### Get lighter colors for rendering a negative magnitude section
            of the given colorKey
            ###
            # Slightly lighter
            c = graphColors(colorKey)
            r = parseInt(c[1..2], 16)
            g = parseInt(c[3..4], 16)
            b = parseInt(c[5..6], 16)
            r += (255 - r) * 0.3
            g += (255 - g) * 0.3
            b += (255 - b) * 0.3
            return @_getColorHex(r, g, b)
            
            
        _getTipSwatch: (name) ->
            tipSwatch = $(
                    '<div class="graph-value-tooltip-swatch">'
                    + '</div>')
                    .css('background-color', 
                            graphColors(name))
            return tipSwatch
            
            
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


        _onLoaded: (callback, dataRaw, timeFrom, timeTo, options) ->
            # callback is where we pass the finished DataGroup.
            # timeTo is passed since it might be defined according to the 
            # request (timeFrom as well).  stats passed to avoid re-parsing.
            {stats, smoothAmt} = options
            self = this

            # Step 1 - Parse the data returned to us into datasets
            dataSetsIn = dataRaw.split(/\n/g)
            dataSetsRaw = []
            actualDiff = null
            for dataSetIn in dataSetsIn
                newSet = dataSetIn.split(/[,\|]/g)
                if newSet.length < 4
                    # Empty / bad line
                    continue
                dataSetsRaw.push(newSet)
                setDiff = parseFloat(newSet[3])
                if not actualDiff?
                    actualDiff = setDiff
                else
                    actualDiff = Math.min(actualDiff, setDiff)

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
            # Default to 10px width for graphs not on dom... fallback for
            # alerts, shouldn't matter
            myWidth = 10
            if @is(':visible')
                myWidth = @width()
            graphPoints = 1 + Math.ceil(myWidth / @GRAPH_POINT_DENSITY)
            pointDiff = ((timeTo - timeFrom) / graphPoints)
            if pointDiff < actualDiff
                pointDiff = actualDiff
            while lastPoint > timeFrom
                pointTimes.unshift(lastPoint)
                lastPoint -= pointDiff
                    
            # Compile expr
            try
                myExpr = evaler.compile(self.config.expr)
            catch e
                message = $("<div>Invalid Expression: 
                        <div>#{ self.config.expr }</div>
                        <div style='color:#f88'>#{ e }</div></div>")
                new ui.Dialog(body: message)
                throw e
            calculateOptions =
                expr: myExpr
                stats: stats
                pointTimes: pointTimes
                statsController: @_statsController

            data = new DataGroup(self.config.title, calculateOptions)
            for dataSet in dataSetsRaw
                # For each of the returned data sets, nest it in our "totals"
                # data set according to the groups we've been asked to divide
                # across
                dataSetData = self._aggregateSourceData(dataSet, pointTimes,
                        timeFrom, smoothAmt)
                if not dataSetData
                    continue
                dataSetName = dataSetData.stat.name
                myGroups = self.config.groups.slice()
                dataOutput = data
                while true
                    # Add set to current DataGroup
                    if not (dataSetName of dataOutput.values)
                        dataOutput.values[dataSetName] = []
                    dataOutput.values[dataSetName].push(dataSetData)

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
                    
            if window.debug
                console.log("data")
                console.log(data)

            callback(data)


        _registerRenderedEvents: (element, events) ->
            ### Register some .on() events on element or its descendants.
            They will be unregistered so that the garbage collector may clean
            up on the next render.
            ###
            @_renderedEventsToClean.push([ element.selectAll("path"), events ])


        _renderedEventsCleanup: () ->
            eventsToClean = @_renderedEventsToClean
            @_renderedEventsToClean = []
            for holder in eventsToClean
                [element, events] = holder
                for ev in events
                    element.on(ev, null)


        _updateAlerts: (data) ->
            # data is a DataGroup object; we are interested in the subgroups.

            # Raises an error if the alert is invalid
            alertEval = @parseAlert(@config.alert, true)
            lastAlerts = @currentAlerts
            @currentAlerts = []
            if alertEval != null
                hideNonAlerted = @dashboard.getHideNonAlerted() or @config.hideNonAlerted
                addDataGroup = (subgroupKey, dg) =>
                    values = dg.getGraphPoints()
                    curVal = values[values.length - 1].y
                    alertInputs = { currentValue: curVal }
                    if alertEval.eval(alertInputs)
                        title = @config.title
                        if subgroupKey?
                            title += " - #{ dg.title }"
                        @currentAlerts.push(
                                "#{title} (#{ @_formatValue(curVal) })")

                        dg.hasAlert = true
                    else if hideNonAlerted and subgroupKey?
                        delete data.subgroups[subgroupKey]
                        for stat, values of data.values
                            newValues = []
                            for v in values
                                if v.groups[@config.groups[0][0]] != subgroupKey
                                    newValues.push(v)
                            data.values[stat] = newValues
                        # Note that we do not need to wipe out old calculations
                        # since the parent will not be calculated (cached) yet

                if @config.groups.length == 0
                    # Not subdivided
                    addDataGroup(null, data)
                else
                    for subgroupId, subgroup of data.subgroups
                        addDataGroup(subgroupId, subgroup)

            if not $.compareObjs(@currentAlerts, lastAlerts)
                @dashboard.app.alertsChanged()


    return Graph


define(reqs, module)

