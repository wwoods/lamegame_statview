reqs = [ "cs!lib/ui", "cs!statsController", "cs!dashboard", "cs!statPathEditor", 
        "cs!optionsEditor", "js-hash/Hash", "css!statsApp", "cs!aliasEditor",
        "cs!alertsDisplay" ]
callback = (ui, StatsController, Dashboard, StatPathEditor, OptionsEditor, 
        Hash, __css__, AliasEditor, AlertsDisplay) ->
    class StatsHeader extends ui.Base
        AUTO_REFRESH_INTERVAL: 300

        constructor: (app, dashboards) ->
            super('<div class="stats-header"></div>')
            @app = app
            @dashboards = dashboards

            @picker = new ui.ListBox(sorted: true).appendTo(@)
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

            @refresh = $('<input type="checkbox" checked="checked">').appendTo(@)
            $('<span style="margin-right:1em;">').text("Autorefresh")
                    .appendTo(@)
            @refresh.bind("change", () =>
                    @hashUpdate()
                    if @refresh.is(':checked')
                        @autoRefreshInterval = @AUTO_REFRESH_INTERVAL
                        @app.dashboard.refresh()
                    else
                        @autoRefreshInterval = 0
            )

            @append("show me ")
            @timeAmt = $('<input type="text" />').appendTo(@)
            @timeAmt.val('1 week')
            @timeAmt.bind "keyup", (e) =>
                if e.which == 13 # enter
                    $('.dashboard').trigger('needs-save')
                    @app.refresh()
            @append(" (hours/days/weeks/years) ")
            
            overDiv = $('<div style="white-space:nowrap;display:inline-block;"></div>')
                .appendTo(@)
            overDiv.append("over ")
            @smoothAmt = $('<input type="text" />').appendTo(overDiv)
            @smoothAmt.val('6 hours')
            @smoothAmt.bind "keyup", (e) =>
                if e.which == 13 # enter
                    $('.dashboard').trigger('needs-save')
                    @app.refresh()
            
            @append('&nbsp;&nbsp;&nbsp;&nbsp;')
            @sanitize = false
            @utcDates = false
            @hideNonAlerted = false
            @columns = 2
            @graphHeight = null
            @autoRefreshInterval = @AUTO_REFRESH_INTERVAL
            @globalFilters = {}
            @globalFilters_doc = "Dict of filters: { group: [ values ] }"
            @optionsEdit = new ui.Base(
                    '<input type="submit" value="Options / Filters" />')
                .appendTo(@)
                .bind("click", () =>
                    new OptionsEditor(
                        filters: @globalFilters
                        statsController: @app._statsController
                        optionsHolder: @
                        onChange: () => app.refresh()
                    )
                )
                .bind("mouseover", (e) =>
                    html = "Filtering on:"
                    for g, vals of @globalFilters
                        if vals.length == 1
                            desc = g + ' = ' + vals[0]
                        else
                            desc = "#{ vals.length } #{ g }s"
                        html += "<br />&nbsp;&nbsp;&nbsp;&nbsp;#{ desc }"
                    if @eventTypesFilter and @eventTypesFilter.length > 0
                        etypes = []
                        for et, i in @eventTypesFilter
                            if i >= 3
                                etypes.push("...and #{ @eventTypesFilter.length\
                                        - i } more")
                                break
                            etypes.push(et)
                        html += "<br />Showing #{ etypes.join(', ') } event " \
                                + "types"
                    ui.Tooltip.show(e, html)
                )
                .bind("mouseout", () => ui.Tooltip.hide())

            @append('&nbsp;&nbsp;&nbsp;&nbsp;Columns: ')
            @columnSub = new ui.Base(
                    '<div class="stats-header-button">-</div>'
                    noSelect: true
                )
                .appendTo(@)
                .bind("click", () =>
                    @columns = Math.max(@columns - 1, 1)
                    @app.dashboard.changeColumns(@columns)
                    @hashUpdate()
                )
            @columnAdd = new ui.Base(
                    '<div class="stats-header-button">+</div>'
                    noSelect: true
                )
                .appendTo(@)
                .bind("click", () =>
                    @columns += 1
                    @app.dashboard.changeColumns(@columns)
                    @hashUpdate()
                )

            @phantom = $('<a href="javascript:void">phantom</a>')
                .appendTo(@)
                .bind "click", =>
                    window.location.href = "/phantom?q=" + encodeURIComponent(Hash.getHash())
                    return false
                
            @pathPicker = new ui.Base(
                    '<input type="submit" value="Add/Edit Stats" 
                        class="stats-header-path-button" />'
                ).appendTo(@)
                .bind("click", () =>
                    @app.editPaths()
                )

            @groupNamer = new ui.Base(
                    '<input type="submit" value="Aliases"
                        class="stats-header-aliases-button" />'
                ).appendTo(@)
                .bind("click", () =>
                    @app.editAliases()
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

            # Clear out timeAmt and smoothAmt so that we'll load the values
            # from the dashboard, or use defaults
            @timeAmt.val('')
            @smoothAmt.val('')

            if newVal == '(new)'
                # Should show some confirmation, but...
                @app.changeDashboard()
                @namer.val('')
                @app.setTitle('Unnamed')
            else
                definition = null
                for d in @dashboards
                    if d.id == newVal
                        definition = d
                        break
    
                if definition
                    @app.changeDashboard(definition)
                    @namer.val(definition.id)
            
            # At this point, we've navigated to a dashboard,
            # so set the hash after letting it load and clear alerts now
            @app.alertsChanged()
            ui.setZeroTimeout () =>
                @hashUpdate()


        dashUpdated: (id, definition) ->
            ### A dashboard was updated remotely (deleted if definition == null)
            ###
            if id == @picker.val() or id == @namer.val()
                @app.dashboard.setSavedDefinition(definition or {})
                @needsSave()

                if @picker.val() == "(unsaved)" and definition?
                    @namer.val(@namer.val() + " - #{ @app.originCode }")
                    new ui.Dialog(body: "Someone else saved this dashboard that
                            you were apparently working on!  To prevent a
                            conflict, your dashboard has been renamed.  You will
                            have to manually merge changes at some point if you
                            save")

            if not definition?
                # Delete!
                @picker.remove(id)
                for d, i in @dashboards
                    if d.id == id
                        @dashboards.splice(i, 1)
                        break
            else
                # Update
                inserted = false
                for d, i in @dashboards
                    if d.id == id
                        @dashboards[i] = definition
                        inserted = true
                        break
                if not inserted
                    @dashboards.push(definition)
                    @picker.addOption(definition.id)
                
                
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
                    origin: @app.originCode
                success: (result) =>
                    if not result.ok
                        return onError(result)
                    @picker.remove(dashId, '(new)')
                error: onError
                
                
        hashUpdate: () ->
            ### Update the hash with a definition of our view.
            ###
            viewDef =
                view: @namer.val()
                timeAmt: @timeAmt.val()
                smoothAmt: @smoothAmt.val()
                columns: @app.dashboard.container.columns
            if @sanitize
                viewDef.sanitize = true
            if @utcDates
                viewDef.utcDates = true
            if @hideNonAlerted
                viewDef.hideNonAlerted = true
            if @graphHeight?
                viewDef.graphHeight = @graphHeight
            if not @refresh.is(':checked')
                viewDef.noAutoRefresh = true
            if not $.compareObjs({}, @globalFilters)
                viewDef.filters = @globalFilters
            if @eventTypesFilter and @eventTypesFilter.length != 0
                viewDef.eventTypes = @eventTypesFilter
            Hash.update(JSON.stringify(viewDef))
                
                
        needsSave: () ->
            ### Called when the current dashboard has been changed and needs
            to be saved.
            ###
            savedDef = @app.dashboard.getSavedDefinition()
            newDef = @app.dashboard.getDefinition()
            newDef.id = @namer.val()

            if not $.compareObjs(savedDef, newDef)
                # Can save!
                if window.debug
                    console.log("Diff defs: ")
                    console.log(savedDef)
                    console.log(newDef)
                if @picker.val() == '(unsaved)'
                    # Already done
                    return
                @picker.addOption('(unsaved)')
                @picker.select('(unsaved)')

                # Since the layout has changed, it is also very possible that
                # alerts have changed.
                @app.alertsChanged()
            else
                # Can't save because it's the same definition!
                @_noRefresh = true
                try
                    @picker.select(@namer.val())
                finally
                    @_noRefresh = false
                @picker.remove('(unsaved)')


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
                    origin: @app.originCode
                success: (result) =>
                    if not result.ok
                        return onError(result)

                    # Saved!  Tell the dashboard and reset the UI for our newly
                    # saved dashboard.
                    @app.dashboard.setSavedDefinition(newDef)

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
                        
                    # Update application title from new ID
                    @app.setTitle(newName)
                    
                    # And get rid of (unsaved) since it's been saved
                    @picker.remove('(unsaved)')

                    # Update our hash
                    @hashUpdate()
                error: onError


    class StatsApp extends ui.Base
        constructor: () ->
            super('<div class="stats-app"></div>')
            self = @
            @siteTitle = document.title
            # Thank you, http://stackoverflow.com/questions/105034/how-to-create-a-guid-uuid-in-javascript
            @originCode = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(
                /[xy]/g, (c) ->
                    r = Math.random()*16|0
                    if c == 'x'
                        v = r
                    else
                        v = (r&0x3|0x8)
                    return v.toString(16)
            )
            window.debug = false

            @alertsDisplay = new AlertsDisplay()
            @alertsDisplay.appendTo('body')

            @text('Loading application, please wait')
            $.ajax(
                'getStartup'
                {
                    success: (data) =>
                        if data.title?
                            $('title').text(data.title)

                        @_statsController = new StatsController(data.stats)
                        @_paths = data.paths
                        @_aliases = data.aliases
                        @_statsController.parseStats(@_paths)
                        @_statsController.setAliases(@_aliases)
                        @_lastActivity = data.lastActivity
                        @_listenForActivities()
                        console.log(@_statsController)
                        window.sc = @_statsController

                        @empty()
                        @header = new StatsHeader(@, data.dashboards)
                                .appendTo(@)

                        $(window).resize(() => @onResize())
                        @onResize()
                                
                        Hash.init((hash, isFirst) => 
                            @_onHashChange(hash, isFirst)
                        )
                        # @dashboard is made in the hash selection
                }
            )


        alertsChanged: () ->
            # Scan all graphs and display alerts
            if not @dashboard?
                return

            allAlerts = []
            for g, i in @dashboard.getGraphs()
                for ca in g.currentAlerts
                    ca.order = i
                allAlerts.push.apply(allAlerts, g.currentAlerts)
            @alertsDisplay.setAlerts(allAlerts)


        changeDashboard: (definition) ->
            # Change to the given dashboard
            if @dashboard?
                @dashboard.remove()
            if definition?
                @setTitle(definition.id)
            cols = @header.columns
            @dashboard = new Dashboard(definition, cols).appendTo(@)
            # Avoid initial set of loads
            @dashboard.bind('needs-save', () => @header.needsSave())


        editAliases: () ->
            ### Edit the @aliases dict
            ###
            new AliasEditor
                app: @
                controller: @_statsController
                aliases: @_aliases
                onChange: () =>
                    @_statsController.setAliases(@_aliases)
            
            
        editPaths: () ->
            ### Edit the @paths list
            ###
            new StatPathEditor
                app: @
                controller: @_statsController
                paths: @_paths
                onChange: () =>
                    @_statsController.parseStats(@_paths)
                    
                    
        onResize: () ->
            ### When the window resizes, the height of the stats-header may
            have changed, meaning we need to adjust our padding-top so that
            all of the graphs are visible.
            ###
            @css
                paddingTop: @header.outerHeight(true)


        refresh: () ->
            # Ensure hash is up to date
            @header.hashUpdate()
            @dashboard.refresh()
                
                
        setTitle: (title) ->
            document.title = title + ' - ' + @siteTitle


        _listenForActivities: () ->
            ### Listen for activities after @_lastActivity
            ###
            $.ajax('getActivities', {
                type: 'POST'
                data: { lastId: @_lastActivity, origin: @originCode }
                success: (data) =>
                    @_lastActivity = data.lastId
                    setTimeout(
                        => @_listenForActivities()
                        1000)
                    for act in data.activities
                        try
                            if act.type == "event" or act.type == "event.delete"
                                @_statsController.events.processActivity(act)
                                # Something changed; refresh graphs if
                                # autorefresh is on
                                if @header.autoRefreshInterval != 0
                                    @dashboard.refresh(true)

                            else if act.type == "dash"
                                @header.dashUpdated(act.data.id, act.data)
                            else if act.type == "dash.delete"
                                @header.dashUpdated(act.data, null)
                            else
                                console.log("Activity:")
                                console.log(act)
                                new ui.Dialog(
                                        body: "Bad activity type: #{ act.type }"
                                )
                        catch e
                            new ui.Dialog(body: e.toString())
                error: =>
                    setTimeout(
                        => @_listenForActivities()
                        1000)
            })
                    
                    
        _onHashChange: (hash, isFirst) ->
            ### Called whenever our address bar hash changes; most of those
            are going to be generated from within our application.  However,
            the caveat is that they should be generated based on a desired
            destination for the user.
            ###
            try
                obj = $.parseJSON(hash)
            catch e
                # Default to no hash, which parseJSON maps to null
                obj = null
            if not obj?
                if isFirst 
                    # Initialize hash by changing picker
                    @header.picker.trigger('change')
            else
                if obj.view?
                    if obj.filters?
                        @header.globalFilters = obj.filters
                    else
                        @header.globalFilters = {}
                    if obj.eventTypes?
                        @header.eventTypesFilter = obj.eventTypes
                    else
                        @header.eventTypesFilter = []
                    if obj.sanitize
                        @header.sanitize = true
                    else
                        @header.sanitize = false
                    if obj.utcDates
                        @header.utcDates = true
                    else
                        @header.utcDates = false
                    if obj.hideNonAlerted
                        @header.hideNonAlerted = true
                    else
                        @header.hideNonAlerted = false
                    if obj.columns
                        @header.columns = obj.columns
                    if obj.graphHeight
                        @header.graphHeight = obj.graphHeight
                    else
                        @header.graphHeight = null
                    if obj.noAutoRefresh
                        @header.refresh.prop("checked", false)
                        @header.autoRefreshInterval = 0
                    else
                        @header.refresh.prop("checked", true)
                        @header.autoRefreshInterval = @header.AUTO_REFRESH_INTERVAL
                    # Apply dashboard before timeAmt and smoothAmt so that they
                    # override the dashboard's settings.
                    @header.picker.select(obj.view)
                    if obj.timeAmt?
                        @header.timeAmt.val(obj.timeAmt)
                    if obj.smoothAmt?
                        @header.smoothAmt.val(obj.smoothAmt)
                else
                    throw "Unknown hash: " + hash
                    

define(reqs, callback)

