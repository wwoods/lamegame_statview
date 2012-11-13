reqs = [ "cs!lib/ui", "cs!statsController", "cs!dashboard", "css!statsApp" ]
callback = (ui, StatsController, Dashboard) ->
    class StatsHeader extends ui.Base
        constructor: (app, dashboards) ->
            super('<div class="stats-header"></div>')
            @app = app
            @dashboards = dashboards

            @picker = new ui.ListBox().appendTo(@)
            @picker.addOption("(new)")
            @picker.addOption("(unsaved)")
            for d in @dashboards
                @picker.addOption(d.id)

            @picker.bind("change", () => @changeDash())
            # Change triggered after we're attached

            @namer = $('<input type="text" />').appendTo(@)
            @saver = $('<input type="submit" value="Save" />').appendTo(@)
            @saver.bind("click", () => @saveDash())

            @refresh = $('<input type="submit" value="Refresh" />').appendTo(@)
            @refresh.bind("click", () => @app.dashboard.refresh())

            @append("show me ")
            @timeAmt = $('<input type="text" />').appendTo(@)
            @timeAmt.val('2 weeks')
            @append(" (hours/days/weeks/years)")

            @append('&nbsp;&nbsp;&nbsp;&nbsp;Columns: ')
            @columnSub = $('<div class="stats-header-button">-</div>')
                .appendTo(@)
                .bind("click", () =>
                    @app.dashboard.changeColumns(-1)
                )
            @columnAdd = $('<div class="stats-header-button">+</div>')
                .appendTo(@)
                .bind("click", () =>
                    @app.dashboard.changeColumns(1)
                )


        changeDash: () ->
            # Called when @picker changes
            newVal = @picker.val()
            if newVal == '(unsaved)' or newVal == @namer.val()
                # No action
                return

            if newVal == '(new)'
                # Should show some confirmation, but...
                @app.changeDashboard()
                @namer.val('')
                return

            definition = null
            for d in @dashboards
                if d.id == newVal
                    definition = d
                    break

            if definition
                @app.changeDashboard(definition)
                @namer.val(definition.id)


        saveDash: () ->
            # Save current dashboard
            newName = @namer.val()
            if newName == ''
                alert("Cannot save empty name")
                throw "Bad input"
            else if newName.toLowerCase() == '(unsaved)' or 
                    newName.toLowerCase() == '(new)'
                alert("Cannot save unsaved or new")
                throw "Bad input"

            newDef = @app.dashboard.getDefinition()
            newDef.id = newName
            onError = (e) =>
                console.log(e)
                alert("Failed to save; see console")
            $.ajax
                type: 'POST'
                url: 'saveDashboard'
                data:
                    dashDef: JSON.stringify(newDef)
                success: (result) =>
                    if not result.ok
                        return onError(result)

                    for d, i in @dashboards
                        if d.id == newName
                            @dashboards.splice(i, 1)
                            break
                    @dashboards.push(newDef)
                    if $('[value="' + newName + '"]', @picker).length == 0
                        @picker.addOption(newName)
                    @picker.select(newName)
                error: onError


    class StatsApp extends ui.Base
        constructor: () ->
            super('<div class="stats-app"></div>')
            self = @

            @_statsController = new StatsController()

            @text('Loading, please wait')
            $.ajax(
                'getStartup'
                {
                    success: (data) =>
                        stats = data.stats
                        window._stats = stats

                        for path in data.paths
                            @_statsController.addStats(path.path, 
                                    path.options)

                        @_statsController.parseStats(stats)
                        console.log(@_statsController)

                        @empty()
                        @header = new StatsHeader(@, data.dashboards).appendTo(
                                @)
                        @header.picker.trigger("change")
                        # @dashboard is made by the header
                }
            )

        changeDashboard: (definition) ->
            # Change to the given dashboard
            oldCols = 2
            if @dashboard?
                oldCols = @dashboard.container.columns
                @dashboard.remove()
            @dashboard = new Dashboard(definition, oldCols).appendTo(@)

define(reqs, callback)

