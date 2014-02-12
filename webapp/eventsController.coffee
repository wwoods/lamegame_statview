
define [ 'cs!lib/ui', 'cs!eventEditor' ], (ui, EventEditor) ->
    class EventsController
        constructor: () ->
            @_minRequested = null
            @_maxRequested = null
            @_events = []
            @_pending = []
            @_inRequest = false


        getEvents: (timeFrom, timeTo) ->
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
                    if not e.delete
                        results.push(e)
                else if e.time > timeTo
                    break

            return results


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
                        callback()
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

                        if replace
                            @_events = data.events
                        else if append
                            @_events = @_events.concat(data.events)
                        else
                            @_events = data.events.concat(@_events)

                        callback()

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
