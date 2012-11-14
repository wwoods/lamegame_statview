reqs = [ "cs!lib/ui", "cs!statsController", "cs!dashboard", "css!statsApp" ]
callback = (ui, StatsController, Dashboard) ->
    class StatsHeader extends ui.Base
        constructor: (app, dashboards) ->
            super('<div class="stats-header"></div>')
            @app = app
            @dashboards = dashboards

            @picker = new ui.ListBox().appendTo(@)
            @picker.addOption("(new)")
            for d in @dashboards
                @picker.addOption(d.id)

            @picker.bind("change", () => @changeDash())
            # Change triggered after we're attached

            @namer = $('<input type="text" />').appendTo(@)
            @saver = $('<input type="submit" value="Save" />').appendTo(@)
            @saver.bind("click", () => @saveDash())
            
            @deleter = $('<input type="submit" value="Delete" />').appendTo(@)
            @deleter.bind("click", () => @deleteDash())

            @refresh = $('<input type="submit" value="Refresh" />').appendTo(@)
            @refresh.bind("click", () => @app.dashboard.refresh())

            @append("show me ")
            @timeAmt = $('<input type="text" />').appendTo(@)
            @timeAmt.val('2 weeks')
            @timeAmt.bind "keyup", (e) =>
                if e.which == 13 # enter
                    @refresh.trigger("click")
            @append(" (hours/days/weeks/years)")

            @append('&nbsp;&nbsp;&nbsp;&nbsp;Columns: ')
            @columnSub = new ui.Base(
                    '<div class="stats-header-button">-</div>'
                    noSelect: true
                )
                .appendTo(@)
                .bind("click", () =>
                    @app.dashboard.changeColumns(-1)
                )
            @columnAdd = new ui.Base(
                    '<div class="stats-header-button">+</div>'
                    noSelect: true
                )
                .appendTo(@)
                .bind("click", () =>
                    @app.dashboard.changeColumns(1)
                )


        changeDash: () ->
            # Called when @picker changes
            newVal = @picker.val()
            if newVal == '(unsaved)' or @_noRefresh
                # No action
                # @_noRefresh signifies that we are in a save operation
                return
                
            # Since we're changing to a defined dashboard, that means we no
            # longer need (unsaved)
            @picker.remove('(unsaved)')

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
                
                
        deleteDash: () ->
            # Delete current dashboard
            dashId = @namer.val()
            if dashId != @picker.val()
                new ui.Dialog(body: "Cannot delete unless name == chosen 
                        dashboard")
                return
                
            new ui.ButtonDialog
                prompt: "Are you sure you want to delete '#{ dashId }'?"
                buttons:
                    "OK": () => @_deleteDash(dashId)
                    "Cancel": null
                
                
        _deleteDash: (dashId) ->
            onError = (e) =>
                console.log(e)
                new ui.Dialog(body: "Failed to delete: " + e)
            $.ajax
                type: 'POST'
                url: 'deleteDashboard'
                data:
                    dashId: dashId
                success: (result) =>
                    if not result.ok
                        return onError(result)
                    @picker.remove(dashId, '(new)')
                error: onError
                
                
        needsSave: () ->
            ### Called when the current dashboard has been changed and needs
            to be saved.
            ###
            if @picker.val() == '(unsaved)'
                # Already done
                return
            @picker.addOption('(unsaved)')
            @picker.select('(unsaved)')


        saveDash: () ->
            # Save current dashboard
            newName = @namer.val()
            if newName == ''
                new ui.Dialog(body: "Cannot save empty name")
                return
            else if newName.toLowerCase() == '(unsaved)' or 
                    newName.toLowerCase() == '(new)'
                new ui.Dialog(body: "Cannot save unsaved or new")
                return
                
            # Does it even need to be saved?
            if newName == @picker.val()
                # Already saved; note that even if picker is not (unsaved),
                # we might just be saving under a different name, which we
                # do want to process
                return
                
            # Already exists?
            exists = false
            for d in @dashboards
                if d.id == newName
                    exists = true
                    break
                    
            if exists
                new ui.ButtonDialog
                    prompt: "Overwrite '#{ newName }'?"
                    buttons:
                        "OK": () => @_saveDash(newName)
                        "Cancel": null
            else
                @_saveDash(newName)


        _saveDash: (newName) ->
            newDef = @app.dashboard.getDefinition()
            newDef.id = newName
            dlg = new ui.Dialog
                body: 'Saving...'
            onError = (e) =>
                dlg.remove()
                console.log(e)
                new ui.Dialog(body: "Failed to save: " + e)
            $.ajax
                type: 'POST'
                url: 'saveDashboard'
                data:
                    dashDef: JSON.stringify(newDef)
                success: (result) =>
                    if not result.ok
                        return onError(result)

                    dlg.remove()
                    for d, i in @dashboards
                        if d.id == newName
                            @dashboards.splice(i, 1)
                            break
                    @dashboards.push(newDef)
                    if $('[value="' + newName + '"]', @picker).length == 0
                        @picker.addOption(newName)
                    @_noRefresh = true
                    try
                        @picker.select(newName)
                    finally
                        @_noRefresh = false
                    
                    # And get rid of (unsaved) since it's been saved
                    @picker.remove('(unsaved)')
                error: onError


    class StatsApp extends ui.Base
        constructor: () ->
            super('<div class="stats-app"></div>')
            self = @

            @text('Loading, please wait')
            $.ajax(
                'getStartup'
                {
                    success: (data) =>
                        if data.title?
                            $('title').text(data.title)

                        @_statsController = new StatsController(data.stats)
                        for path in data.paths
                            @_statsController.addStats(path.path, 
                                    path.options)
                        @_statsController.parseStats(@stats)
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
            # Avoid initial set of loads
            @dashboard.bind('needs-save', () => @header.needsSave())

define(reqs, callback)

