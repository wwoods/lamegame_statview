define [ 'cs!lib/ui', 'css!controls' ], (ui) ->
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

            @bind('click', () =>
                # Stop it from affecting graph
                return false
            )

            @_expandCollapse.bind('click', () =>
                @_content.show()
                @refresh()
                    
                ui.Shade.show(@_content, hide: () =>
                    ok.trigger("click")
                    @_content.hide()
                )
            )

            timeDiv = $('<div>Show last </div>')
            timeDivAmt = $('<input type="text" />').appendTo(timeDiv)
            # COMMENTED!  Dashboard has an overall time, no need for this
            #@_content.append(timeDiv)

            @_content.append("Title: ")
            @title = $('<input type="text" />').appendTo(@_content)
            @title.css
                width: '200px'
            @title.val('(unnamed)')

            @_content.append('<br />')

            @type = new ui.ListBox()
            @type.addOption "area-zoom", "Area Zoom"
            @type.addOption "linear-zoom", "Linear Zoom"
            @type.addOption "area", "Area"
            @_content.append(@type)

            @_content.append('<br />')

            @statsLb = new ui.ListBox(multiple: true)
            @_content.append(@statsLb)
            @statsLb.delegate "option", "click", ->
                # Not fat arrow, need this from event
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

            @groupsActive = new ui.Base("<div></div>")
            @groupsActive.delegate "div", "click", ->
                $(this).remove()

            @_content.append "<div>Groups</div>"
            @_content.append @groupsActive
            @_content.append "<div>Groups Available</div>"
            @groupList = new ui.ListBox(multiple: true)
            @_content.append @groupList
                
            @groupList.delegate "option", "click", ->
                # Don't use fat arrow, this refers to obj clicked
                self._addGroupFilter($(this).val())

            smootherDiv = $("<div></div>").appendTo(@_content)
            smootherDiv.append "Smooth hours: "
            smoother = $("<input type=\"text\" />").appendTo(smootherDiv)
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
                        new Graph(@_graph.config), @)
                ui.Shade.hide()
            deleter = new ui.Base('<input type="button" value="Delete" />')
            deleter.css
                position: 'relative'
                float: 'right'
            @_content.append(deleter)
            deleter.bind "click", () =>
                @uiClosest('.dashboard-cell').remove()

            # Populate initial fields from graph
            options = @_graph.config
            @type.select(options.type)
            @title.val(options.title)
            @expr.val(options.expr)
            smoother.val(options.smoothOver)
            timeDivAmt.val(options.timeAmt)
            # Wait to trigger expr change and update groups available until
            # we're in the dom and visible (in @_expandCollapseButton)

            # Bind refresh button
            ok.bind 'click', () =>
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
                    groups: groups
                    smoothOver: smoother.val()
                    timeAmt: timeDivAmt.val()
                    autoRefresh: 300

                @_graph.update options

            @_content.hide()
            if autoExpand
                @_expandCollapse.trigger("click")
                
                
        refresh: () ->
            # Called when shown, refresh since stat configuration may
            # have changed.
            @statsLb.reset()
            for name of @_statsController.stats
                @statsLb.addOption name
                
            @expr.trigger("change")
            # And add the groups we're actually using
            @groupsActive.empty()
            for grp in @_graph.config.groups
                @_addGroupFilter(grp[0], grp[1])


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
            g = $("<div></div>").text(group).appendTo(@groupsActive)
          
            # Stop click from removing the row
            $("<input class=\"regex\" type=\"text\" />").bind("click", ->
                false
            ).appendTo(g).val(filter)

