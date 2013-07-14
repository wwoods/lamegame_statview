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

            @toggleClass('ok', alerts.length == 0)
            @toggleClass('collapsed', alerts.length == 0)
            @_lastAlerts = alerts[..]


        toggle: () ->
            @toggleClass('collapsed')
