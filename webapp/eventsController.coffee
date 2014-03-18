
define [ 'cs!lib/ui', 'cs!eventEditor' ], (ui, EventEditor) ->
    class EventsController
        constructor: () ->
            @_minRequested = null
            @_maxRequested = null
            @_events = []
            @_pending = []
            @_inRequest = false
            # user is always a type
            @_types = { user: true }

            # Seed our types values from events in the last week
            now = Date.now() / 1000
            @loadEvents(now - 7 * 86400, now)


        addType: (t) ->
            # Registers a new filter type.  Returns true if it wasn't in there
            isNew = t of @_types
            @_types[t] = true
            return isNew


        getEvents: (timeFrom, timeTo, typeFilter = null) ->
            # Returns a sorted list of events between the two times given.
            # Throws an error if loadEvents() hasn't been called with
            if timeFrom >= @_maxRequested or timeTo < @_minRequested
                throw new Error("Events have not been requested for the given "\
                        + "timeframe.  Please ensure loadEvents() has been "\
                        + "called first")
            firstI = null
            lastI = @_events.length
            results = []
            for e, i in @_events
                if e.time >= timeFrom and e.time <= timeTo
                    isOk = not e.delete
                    if isOk and typeFilter? and typeFilter.length > 0
                        isOk = false
                        for t in typeFilter
                            if t in e.types
                                isOk = true
                                break
                    if isOk
                        results.push(e)
                else if e.time > timeTo
                    break

            return results


        getTypes: () ->
            # Returns a sorted list of event types to display, based on loaded
            # events.
            r = []
            for t of @_types
                r.push(t)
            r.sort (a, b) -> a.toLowerCase().localeCompare(b.toLowerCase())
            return r


        loadEvents: (timeFrom, timeTo, callback) ->
            if @_inRequest
                @_pending.push([ timeFrom, timeTo, callback ])
                return

            replace = false
            append = true
            if @_minRequested != null
                if timeTo <= @_maxRequested and timeFrom >= @_minRequested
                    # Overlapping, do nothing
                    try
                        callback? and callback()
                    finally
                        if @_pending.length > 0
                            @loadEvents.apply(@, @_pending.shift())
                    return

                timeFrom = Math.min(timeFrom, @_maxRequested)
                timeTo = Math.max(timeTo, @_minRequested)

                if timeFrom <= @_minRequested and timeTo >= @_maxRequested
                    replace = true
                else if @_minRequested <= timeFrom
                    timeFrom = @_maxRequested
                else if @_maxRequested >= timeTo
                    timeTo = @_minRequested

                @_maxRequested = Math.max(@_maxRequested, timeTo)
                @_minRequested = Math.min(@_minRequested, timeFrom)

                if timeTo <= @_maxRequested
                    append = false
            else
                @_minRequested = timeFrom
                @_maxRequested = timeTo

            @_inRequest = true
            $.ajax(
                'getEvents'
                {
                    data: { timeFrom, timeTo },
                    type: 'POST',
                    success: (data) =>
                        # data.events are sorted, so...
                        if data.error?
                            new ui.Dialog(
                                body: "Could not load events: #{ e }"
                            )
                            return

                        for e in data.events
                            if not e.types? or e.types.length == 0
                                # Old data; instantiate types to its default
                                e.types = [ 'user' ]
                            @_registerTypes(e.types)

                        if replace
                            @_events = data.events
                        else if append
                            @_events = @_events.concat(data.events)
                        else
                            @_events = data.events.concat(@_events)

                        callback? and callback()

                    complete: () =>
                        @_inRequest = false
                        if @_pending.length > 0
                            @loadEvents.apply(@, @_pending.shift())
                }
            )


        newEvent: (timeAt, callback) ->
            # Give user option of making a new event at timeAt, calling callback
            # if they save.

            event = { time: timeAt }
            onAdd = =>
                added = false
                for v, i in @_events
                    if timeAt < v.time
                        @_events.splice(i, 0, event)
                        added = true
                        break
                if not added
                    @_events.push(event)
                callback? and callback()
            new EventEditor(event, onAdd)


        processActivity: (act) ->
            if (@_minRequested == null \
                    or act.data.time < @_minRequested \
                    or act.data.time > @_maxRequested)
                # Not yet loaded, get it when we get it
                return

            if act.type == "event"
                inserted = false
                for e, i in @_events
                    if e.time >= act.data.time
                        inserted = true
                        @_events.splice(i, 0, act.data)
                        break
                if not inserted
                    @_events.push(act.data)
            else if act.type == "event.delete"
                for e in @_events
                    if e._id == act.data
                        e.delete = true
                        break
            else
                throw new Error("Unrecognized activity type: #{ act.type }")


        _registerTypes: (types) ->
            for t in types
                @_types[t] = true
