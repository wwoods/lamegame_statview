define [ 'cs!lib/ui', 'cs!alertEvaluator', 'css!controls' ], (ui) ->
    class Controls extends ui.Base
        constructor: (graph, autoExpand) ->
            super('<div class="controls"></div>')
            self = @

            @_graph = graph
            @_statsController = graph._statsController

            @_expandCollapse = $('<div class="controls-collapse"></div>')
            @append(@_expandCollapse)
            @_content = $('<div class="controls-content"></div>')
            @append(@_content)

            @_content.bind('click mousedown', (e) =>
                # Stop it from affecting graph, but do let the default action
                # happen for e.g. inputs
                e.stopPropagation();
            )

            @_expandCollapse.bind('click', () =>
                @_content.show()
                @refresh()

                @_content.css(left: 0)
                if (@_content.offset().left + @_content.outerWidth() \
                        > $(window).width())
                    @_content.css(left: -@_content.outerWidth())

                if @_content.offset().left < 0
                    # Would be off left side of screen
                    @_content.css(left: 0)
                    
                ui.Shade.show(@_content, hide: () =>
                    try
                        @_graph.update @getOptions()
                    catch e
                        # Do nothing, user will get an error message
                        null
                    @_content.hide()
                )
            )

            @_content.append("Title: ")
            @title = $('<input type="text" />').appendTo(@_content)
            @title.css
                width: '200px'
            @title.val('(unnamed)')

            utilPane = $('<div class="controls-util"></div>')
            $('<input type="submit" value="Copy" />')
                .bind("click", () => window.prompt(
                        "Copy following definition: ",
                        JSON.stringify(@getOptions())))
                .appendTo(utilPane)
            $('<input type="submit" value="Restore from clipboard" />')
                .bind("click", () =>
                    def = window.prompt("Paste here: ")
                    $.extend(@_graph.config, JSON.parse(def))
                    @_updateFieldsFromGraph()
                    @refresh()
                )
                .appendTo(utilPane)
            @_content.append(utilPane)

            @_content.append('<br style="clear:both;"/>')

            @type = new ui.ListBox()
            @type.addOption "linear-zoom", "Linear Zoom"
            @type.addOption "area-zoom", "Area Zoom"
            @type.addOption "area-period", "Area Periods (partial support)"
            # Not currently supported; @type.addOption "area", "Area"
            @_content.append(@type)

            @_content.append('<br />')

            @statsLb = new ui.ListBox(multiple: true)
            @_content.append(@statsLb)
            @statsLb.delegate "option", "click", ->
                # Not fat arrow, need this from event
                # Only add our value to self.expr if we are currently NOT a
                # valid expression.  If we are a valid expression, appending
                # the stat will make it invalid, meaning this is probably not
                # what the user wanted.
                if not self._graph.isValidExpr(self.expr.val())
                    self.expr.val(self.expr.val() + $(this).val())
                    self.expr.trigger('change')
                    self.expr.focus()

            exprDiv = $('<div>Expression</div>').appendTo(@_content)
            @_statsFound = []
            @expr = new ui.TextBox
                    multiline: true
                    expand:  true
                    minWidth: 100
                    maxWidth: 250
                .appendTo(exprDiv)
            @expr.bind "change keyup", =>
                @updateExpression(@expr.val())

            @groupsActive = new ui.Base('<ul class="groups-active"></ul>')
            @groupsActive.delegate "li", "click", ->
                $(this).remove()

            @_content.append "<div>Group by</div>"
            @_content.append @groupsActive
            @_content.append "<div>Groups Available</div>"
            @groupList = new ui.ListBox(multiple: true)
            @_content.append @groupList
                
            @groupList.delegate "option", "click", ->
                # Don't use fat arrow, this refers to obj clicked
                self._addGroupFilter($(this).val())

            smootherDiv = $("<div></div>").appendTo(@_content)
            smootherDiv.append "Smooth hours: "
            @smoother = $("<input type=\"text\" />").appendTo(smootherDiv)

            timeDiv = $('<div>Show last </div>')
            @timeDivAmt = $('<input type="text" />').appendTo(timeDiv)
            @_content.append(timeDiv)

            alerts = $('<div class="controls-alert">').appendTo(@_content)
            alerts.append('Alert if: ')
            @alert = $('<input type="text">').appendTo(alerts)
            @alert.bind "change keyup", =>
                @updateAlert(@alert.val())
            hideNonAlerts = $('<div>').appendTo(alerts)
            @hideNonAlerted = $('<input type="checkbox" />').appendTo(
                    hideNonAlerts)
            $("<span>Hide lines not failing alert</span>")
                    .appendTo(hideNonAlerts)
                    .bind "click", =>
                        @hideNonAlerted.prop('checked',
                                not @hideNonAlerted.prop('checked'))

            helpDiv = $("<div>Graph Help</div>")
                    .appendTo(@_content)
            @helpText = $("<textarea>").appendTo(helpDiv)
                    .css(height: '5em')

            ok = new ui.Base("<input type=\"button\" value=\"Refresh\" />")
            @_content.append ok

            cloner = new ui.Base('<input type="button" value="Clone" />')
            cloner.css
                position: 'relative'
                float: 'right'
            @_content.append(cloner)
            cloner.bind "click", () =>
                Graph = require("cs!graph")
                @uiClosest('.dashboard-container').append(
                        new Graph(@_graph.config, @_graph.dashboard), @)
                ui.Shade.hide()
            deleter = new ui.Base('<input type="button" value="Delete" />')
            deleter.css
                position: 'relative'
                float: 'right'
            @_content.append(deleter)
            deleter.bind "click", () =>
                @uiClosest('.dashboard-cell').remove()

            # Populate fields from graph
            @_updateFieldsFromGraph()
            # Wait to trigger expr change and update groups available until
            # we're in the dom and visible (in @_expandCollapseButton)

            # Bind refresh button
            ok.bind 'click', () =>
                ui.Shade.hide()

            @_content.hide()
            if autoExpand
                ui.setZeroTimeout => @_expandCollapse.trigger("click")


        getOptions: () ->
            # Returns the options specified; that is, the complete graph
            # specification
            stat = @_statsController.stats[@statsLb.val()]
            groups = []
            @groupsActive.children().each ->
                filter = $(".regex", $(this)).val()
                groups.push [$(this).text(), filter]

            options =
                title: @title.val()
                type: @type.val()
                stats: @_statsFound
                expr: @expr.val()
                alert: @alert.val()
                hideNonAlerted: @hideNonAlerted.prop('checked')
                groups: groups
                smoothOver: @smoother.val()
                timeAmt: @timeDivAmt.val()
                autoRefresh: ''
                helpText: @helpText.val()
            return options
                
                
        refresh: () ->
            # Called when shown, refresh since stat configuration may
            # have changed, meaning the user has different options available.
            @statsLb.reset()
            for name of @_statsController.stats
                @statsLb.addOption name
                
            @expr.trigger("change")
            # And add the groups we're actually using
            @groupsActive.empty()
            for grp in @_graph.config.groups
                @_addGroupFilter(grp[0], grp[1])


        updateAlert: (expr) ->
            p = @_graph.parseAlert(expr)
            if p == null
                @alert.addClass('wrong')
            else
                @alert.removeClass('wrong')


        updateExpression: (expr) ->
            @groupsActive.empty()
            @groupList.reset()

            @_statsFound = @_graph.parseStats(expr)
            for stat in @_statsFound
                i = 0
                m = stat.groups.length
                while i < m
                    if (
                            $('[value=' + stat.groups[i] + ']', @groupList).length == 0
                            )
                        @groupList.addOption stat.groups[i]
                    i++
                    
                    
        _addGroupFilter: (group, filter = "") ->
            # Add a filter to the UI.  Done through either clicking group
            # in list, or during load
            g = $("<li></li>").text(group).appendTo(@groupsActive)
          
            # Stop click from removing the row
            $("<input class=\"regex\" type=\"text\" />").bind("click", ->
                false
            ).appendTo(g).val(filter)


        _updateFieldsFromGraph: () ->
            options = @_graph.config
            @type.select(options.type)
            @title.val(options.title)
            @expr.val(options.expr)
            @alert.val(options.alert)
            @smoother.val(options.smoothOver)
            @timeDivAmt.val(options.timeAmt)
            @helpText.val(options.helpText or '')
            @hideNonAlerted.prop('checked', options.hideNonAlerted)

