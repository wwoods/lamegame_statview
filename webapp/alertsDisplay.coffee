define [ "cs!lib/ui", "css!alertsDisplay" ], (ui) ->
    class AlertsDisplay extends ui.Base
        constructor: () ->
            super('<div class="alerts-display">')
            @bind 'click', => @toggle()
            @_lastAlerts = null
            @setAlerts([])


        setAlerts: (alerts) ->
            if $.compareObjs(alerts, @_lastAlerts)
                return

            @empty()
            for a in alerts
                $('<div>').text(a).appendTo(@)

            wasOk = @hasClass('ok')
            if alerts.length == 0
                # Always collapse if OK
                @addClass('ok')
                @addClass('collapsed')
            else
                @removeClass('ok')
                # If we were collapsed previously, and we were ok before, then
                # pop up now.  Otherwise, flash if collapsed
                if @hasClass('collapsed')
                    if wasOk
                        @removeClass('collapsed')
                    else
                        cycle = [ 0 ]
                        cycler = () =>
                            delay = 200
                            if cycle[0] % 2 == 0
                                @css(backgroundColor: '#f00')
                            else
                                @css(backgroundColor: '')
                                delay = 300
                            cycle[0] += 1
                            if cycle < 6
                                setTimeout(
                                    cycler
                                    delay)

                        cycler()

            @_lastAlerts = alerts[..]


        toggle: () ->
            @toggleClass('collapsed')
